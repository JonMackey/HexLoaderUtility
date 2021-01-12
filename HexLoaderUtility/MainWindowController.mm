/*******************************************************************************
	License
	****************************************************************************
	This program is free software; you can redistribute it
	and/or modify it under the terms of the GNU General
	Public License as published by the Free Software
	Foundation; either version 3 of the License, or
	(at your option) any later version.
 
	This program is distributed in the hope that it will
	be useful, but WITHOUT ANY WARRANTY; without even the
	implied warranty of MERCHANTABILITY or FITNESS FOR A
	PARTICULAR PURPOSE. See the GNU General Public
	License for more details.
 
	Licence can be viewed at
	http://www.gnu.org/licenses/gpl-3.0.txt

	Please maintain this license information along with authorship
	and copyright notices in any redistribution of this code
*******************************************************************************/
//
//  MainWindowController.m
//  HexLoaderUtility
//
//  Created by Jon on 10/20/2020.
//  Copyright © 2020 Jon Mackey. All rights reserved.
//
/*
	On startup the temporary folder is scanned to locate sketches compiled by
	the current Arduino IDE instance (so, obviously, if the Arduino IDE isn't
	running there won't be any compiled sketches.)
	A UI table entry is created for each compiled sketch found.  The lifespan of
	the compiled sketch is for as long as it exists in the temporary folder.
	When the Arduino IDE process ends it cleans up the temporary folder by
	removing all compiled sketches and cached core folders.
	
	The temporary folder is monitored using notifications from NSFileCoordinator.
*/
#import "MainWindowController.h"
#include "AVRElfFile.h"
#include "ConfigurationFile.h"
#include "AvrdudeConfigFile.h"
#include "FileInputBuffer.h"
#include "JSONElement.h"

// Defining AVR_OBJ_DUMP will run avr-objdump for all elf files.
// Saved as xxxM.ino.elf.txt, where xxx is the sketch name.
#define AVR_OBJ_DUMP	1

@interface MainWindowController ()

@end

@implementation MainWindowController

#if SANDBOX_ENABLED
NSString *const kTempFolderURLBMKey = @"tempFolderURLBM";
NSString *const kPackagesFolderURLBMKey = @"packagesFolderURLBM";
NSString *const kArduinoAppURLBMKey = @"arduinoAppURLBM";
//NSString *const kSavedSketchesURLBMKey = @"savedSketchesURLBM";
NSString *const kExportFolderURLBMKey = @"exportFolderURLBM";
#else
NSString *const kArduinoAppPathKey = @"arduinoAppPath";
//NSString *const kSavedSketchesPathKey = @"savedSketchesPath";
NSString *const kExportFolderPathKey = @"exportFolderPath";
#endif
NSString *const kArduinoBundleIdentifier = @"cc.arduino.Arduino";
NSString *const kSelectPrompt = @"Select";
extern NSUInteger const kNumTableColumns;
extern NSString *const kNameKey;
extern NSString *const kLengthKey;
extern NSString *const kIDKey;
extern NSString *const kSpeedKey;
extern NSString *const kBaudRateKey;
extern NSString *const kSignatureKey;
extern NSString *const kDeviceNameKey;
//NSString *const kSourceBMKey = @"sourceBM";
NSString *const kTempURLKey = @"tempURL";
NSString *const kTempCopyURLKey = @"tempCopyURL";
NSString *const kFQBNKey = @"FQBN";

const NSUInteger	kArduinoPathControlTag = 1;
const NSUInteger	kTempFolderPathControlTag = 2;
const NSUInteger	kPackagesFolderPathControlTag = 3;
const NSUInteger	kExportFolderPathControlTag = 4;
const NSUInteger	kShowArduinoTempFolderTag = 93;

struct SMenuItemDesc
{
	NSInteger	mainMenuTag;
	NSInteger	subMenuTag;
    SEL action;
};

SMenuItemDesc	menuItems[] = {
	{1,11, @selector(exportHex:)},
	{1,12, @selector(exportElfObj:)}
};

BoardsConfigFiles* _configFiles;
AvrdudeConfigFiles* _avrdudeConfigFiles;

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	_configFiles = new BoardsConfigFiles;
	_avrdudeConfigFiles = new AvrdudeConfigFiles;
	{
		const SMenuItemDesc*	miDesc = menuItems;
		const SMenuItemDesc*	miDescEnd = &menuItems[sizeof(menuItems)/sizeof(SMenuItemDesc)];
		for (; miDesc < miDescEnd; miDesc++)
		{
			NSMenuItem *menuItem = [[[NSApplication sharedApplication].mainMenu itemWithTag:miDesc->mainMenuTag].submenu itemWithTag:miDesc->subMenuTag];
			if (menuItem)
			{
				// Assign this object as the target.
				menuItem.target = self;
				menuItem.action = miDesc->action;
			}
		}
		/*
		*	Assign this object as the File menu delegate for enabling/disabling
		*	the Export menu item.
		*/
		//[[NSApplication sharedApplication].mainMenu itemWithTag:1].submenu.delegate = self;
	}

	if (self.hexLoaderTableViewController == nil)
	{
		_hexLoaderTableViewController = [[HexLoaderUtilityTableViewController alloc] initWithNibName:@"HexLoaderUtilityTableViewController" bundle:nil];
		// embed the current view to our host view
		[sketchesView addSubview:[self.hexLoaderTableViewController view]];
		
		// make sure we automatically resize the controller's view to the current window size
		[[self.hexLoaderTableViewController view] setFrame:[sketchesView bounds]];
	}

	{
		NSMenu*	tableContextualMenu = _hexLoaderTableViewController.tableView.menu;
		NSMenuItem *menuItem = [tableContextualMenu itemWithTag:91];
		if (menuItem)
		{
			// Assign this object as the target.
			menuItem.target = self;
			menuItem.action = @selector(exportHex:);
		}
		menuItem = [tableContextualMenu itemWithTag:92];
		if (menuItem)
		{
			// Assign this object as the target.
			menuItem.target = self;
			menuItem.action = @selector(dumpConfig:);
		}
		menuItem = [tableContextualMenu itemWithTag:93];
		if (menuItem)
		{
			// Assign this object as the target.
			menuItem.target = self;
			menuItem.action = @selector(showInFinder:);
		}
		menuItem = [tableContextualMenu itemWithTag:94];
		if (menuItem)
		{
			// Assign this object as the target.
			menuItem.target = self;
			menuItem.action = @selector(exportElfObj:);
		}
	}
	if (self.hexLoaderLogViewController == nil)
	{
		_hexLoaderLogViewController = [[HexLoaderUtilityLogViewController alloc] initWithNibName:@"HexLoaderUtilityLogViewController" bundle:nil];
		// embed the current view to our host view
		[serialView addSubview:[self.hexLoaderLogViewController view]];

		// make sure we automatically resize the controller's view to the current window size
		[[self.hexLoaderLogViewController view] setFrame:[serialView bounds]];
	}
	[self verifyTempFolder];
	[self verifyPackagesFolder];
	[self verifyArduinoApp];
	{
		NSString*	folderPath = [[NSUserDefaults standardUserDefaults] objectForKey:kExportFolderPathKey];
		if (folderPath)
		{
			_exportFolderURL = [NSURL fileURLWithPath:folderPath isDirectory:YES];
			exportFolderPathControl.URL = _exportFolderURL;
		}
	}
	self.hexLoaderTableViewController.tempFolderURL = _tempFolderURL;
	_updateTimer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(checkForTempFolderChanges:) userInfo:nil repeats:YES];
	[self doUpdate];
}

/*********************************** dealloc **********************************/
- (void)dealloc
{
    delete _configFiles;
    delete _avrdudeConfigFiles;
}

/************************** checkForTempFolderChanges *************************/
- (void)checkForTempFolderChanges:(NSTimer *)inTimer
{
	/*
	*	If the temp folder has changed AND
	*	this application is active/frontmost THEN
	*	Update the sketches list.
	*/
	if (self.hexLoaderTableViewController.tempFolderChanged &&
		[NSApplication sharedApplication].active)
	{
		self.hexLoaderTableViewController.tempFolderChanged = NO;
		[self doUpdate];
		//NSLog(@"_tempFolderChanged\n");
	}
}

/******************************** awakeFromNib ********************************/
- (void)awakeFromNib
{
	[super awakeFromNib];
}

#pragma mark - Path Popup support
/**************************** willDisplayOpenPanel ****************************/
- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel
{
	_openTag = pathControl.tag;
	if (pathControl.tag == kArduinoPathControlTag)
	{
		NSArray* appFolderURLs =[[NSFileManager defaultManager] URLsForDirectory:NSApplicationDirectory inDomains:NSLocalDomainMask];
		[openPanel setCanChooseDirectories:NO];
		[openPanel setCanChooseFiles:YES];
		[openPanel setAllowsMultipleSelection:NO];
		openPanel.directoryURL = appFolderURLs[0];
		openPanel.delegate = self;
		openPanel.message = @"Locate the Arduino Application";
		openPanel.prompt = kSelectPrompt;
	} else if (pathControl.tag == kExportFolderPathControlTag)
	{
		[openPanel setCanChooseDirectories:YES];
		[openPanel setCanChooseFiles:NO];
		[openPanel setAllowsMultipleSelection:NO];
		[openPanel setCanCreateDirectories:YES];
		NSString*	folderPath = [[NSUserDefaults standardUserDefaults] objectForKey:kExportFolderPathKey];
		if (folderPath)
		{
			openPanel.directoryURL = [NSURL fileURLWithPath:folderPath isDirectory:YES];
		}
		openPanel.delegate = self;
		openPanel.message = @"Locate the Export Folder";
		openPanel.prompt = kSelectPrompt;
	}
}

/******************************** validateURL *********************************/
// The user just selected the Arduino app or the export folder.
- (BOOL)panel:(id)sender validateURL:(NSURL *)inURL error:(NSError * _Nullable *)outError
{
	BOOL success = NO;
	if (_openTag == kArduinoPathControlTag)
	{
		NSURL*	arduinoAppURL = inURL;
		// The user just selected the app so it's in the sandbox.
		// Verify that the CFBundleIdentifier is cc.arduino.Arduino
		NSURL* infoPListURL = [NSURL fileURLWithPath:[arduinoAppURL.path stringByAppendingPathComponent:@"Contents/Info.plist"] isDirectory:NO];
		NSDictionary*	plist = [NSDictionary dictionaryWithContentsOfURL:infoPListURL];
		if (plist &&
			[(NSString*)[plist objectForKey:@"CFBundleIdentifier"] isEqualToString:kArduinoBundleIdentifier])
		{
			NSError*	error = nullptr;
	#if SANDBOX_ENABLED
			NSData*	arduinoAppURLBM = [arduinoAppURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
					includingResourceValuesForKeys:NULL relativeToURL:NULL error:&error];
			[[NSUserDefaults standardUserDefaults] setObject:arduinoAppURLBM forKey:kArduinoAppURLBMKey];
	#else
			[[NSUserDefaults standardUserDefaults] setObject:arduinoAppURL.path forKey:kArduinoAppPathKey];
	#endif
			if (error)
			{
				NSLog(@"-selectArduinoApp- %@\n", error);
				[[NSUserDefaults standardUserDefaults] removeObjectForKey:kArduinoAppPathKey];
				NSAlert *alert = [[NSAlert alloc] init];
				[alert setMessageText:@"Arduino Application"];
				[alert setInformativeText:@"A valid Arduino application was not selected."];
				[alert addButtonWithTitle:@"OK"];
				[alert setAlertStyle:NSAlertStyleWarning];
				[alert runModal];
			}
			success = !error;
		}
	} else if (_openTag == kExportFolderPathControlTag)
	{
		NSURL*	folderURL = inURL;
		NSError*	error = nullptr;
	#if SANDBOX_ENABLED
		NSError*	error;
		NSData*	folderURLBM = [folderURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
				includingResourceValuesForKeys:NULL relativeToURL:NULL error:&error];
		[[NSUserDefaults standardUserDefaults] setObject:folderURLBM forKey:kExportFolderURLBMKey];
	#else
		[[NSUserDefaults standardUserDefaults] setObject:folderURL.path forKey:kExportFolderPathKey];
		_exportFolderURL = folderURL;
	#endif
		success = !error;
	}
	return(success);
}

/******************************* willPopUpMenu ********************************/
- (void)pathControl:(NSPathControl *)pathControl willPopUpMenu:(NSMenu *)menu
{
	if (pathControl.tag == kTempFolderPathControlTag ||
		pathControl.tag == kPackagesFolderPathControlTag ||
		(pathControl.tag == kExportFolderPathControlTag && [[NSUserDefaults standardUserDefaults] objectForKey:kExportFolderPathKey]))
	{
		NSMenuItem *showInFinderMenuItem = [[NSMenuItem alloc]initWithTitle:@"Show in Finder" action:@selector(showInFinder:) keyEquivalent:[NSString string]];
		showInFinderMenuItem.target = self;
		showInFinderMenuItem.tag = pathControl.tag;
		if (pathControl.tag != 4)
		{
			[menu insertItem:[NSMenuItem separatorItem] atIndex:0];
			[menu insertItem:showInFinderMenuItem atIndex:0];
		} else
		{
			[menu insertItem:showInFinderMenuItem atIndex:1];
		}
	}
}

/******************************* showInFinder *********************************/
- (IBAction)showInFinder:(id)sender
{
	NSURL*	folderURL = nil;
	switch (((NSMenuItem*)sender).tag)
	{
		case kTempFolderPathControlTag:
			folderURL = _tempFolderURL;
			break;
		case kPackagesFolderPathControlTag:
			folderURL = _packagesFolderURL;
			break;
		case kExportFolderPathControlTag:
			folderURL = _exportFolderURL;
			break;
		case kShowArduinoTempFolderTag:
		{
			NSUInteger selectedRow = _hexLoaderTableViewController.tableView.selectedRow;
			NSMutableDictionary*	sketchRec = _hexLoaderTableViewController.sketches[selectedRow];
			if (sketchRec)
			{
				folderURL = (NSURL*)sketchRec[kTempURLKey];
			}
			break;
		}
	}
	if (folderURL)
	{
	#if SANDBOX_ENABLED
			if ([folderURL startAccessingSecurityScopedResource])
			{
				[[NSWorkspace sharedWorkspace] openURL:folderURL];
				[folderURL stopAccessingSecurityScopedResource];
			}
		}
	#else
		[[NSWorkspace sharedWorkspace] openURL:folderURL];
	#endif
	}
}

/****************************** verifyTempFolder ******************************/
/*
*	This makes sure the previous temporary folder still exists.  If it no
*	longer exists the user will be asked to select it.
*/
- (void)verifyTempFolder
{
#if SANDBOX_ENABLED
	NSString*	tempFolderPath = [[[NSFileManager defaultManager] temporaryDirectory].path stringByDeletingLastPathComponent];
	NSURL*	tempFolderURL = NULL;
	NSData*	tempFolderURLBM = [[NSUserDefaults standardUserDefaults] objectForKey:kTempFolderURLBMKey];
	if (tempFolderURLBM)
	{
		tempFolderURL = [NSURL URLByResolvingBookmarkData: tempFolderURLBM
				options:NSURLBookmarkResolutionWithoutUI+NSURLBookmarkResolutionWithoutMounting+NSURLBookmarkResolutionWithSecurityScope
						relativeToURL:NULL bookmarkDataIsStale:NULL error:NULL];
	}
	// stringByStandardizingPath will remove /private from the path. NSFileManager
	// seems to be standardizing the URL it returns.
	BOOL	success = tempFolderURL && [[tempFolderURL.path stringByStandardizingPath] isEqualToString:tempFolderPath];
	if (!success)
	{
		NSOpenPanel*	openPanel = [NSOpenPanel openPanel];
		if (openPanel)
		{
			[openPanel setCanChooseDirectories:YES];
			[openPanel setCanChooseFiles:NO];
			[openPanel setAllowsMultipleSelection:NO];
			openPanel.showsHiddenFiles = YES;
			openPanel.directoryURL = [NSURL fileURLWithPath:tempFolderPath isDirectory:YES];
			openPanel.message = @"Because of sandbox issues, we need to get permission to access the temporary items folder. Please press Select.";
			openPanel.prompt = kSelectPrompt;
			//[openPanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result)
			{
				if ([openPanel runModal] == NSModalResponseOK)
				{
					NSArray* urls = [openPanel URLs];
					if ([urls count] == 1)
					{
						NSError*	error;
						tempFolderURL = urls[0];
						if ([[tempFolderURL.path stringByStandardizingPath] isEqualToString:tempFolderPath])
						{
							tempFolderURLBM = [tempFolderURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
									includingResourceValuesForKeys:NULL relativeToURL:NULL error:&error];
							[[NSUserDefaults standardUserDefaults] setObject:tempFolderURLBM forKey:kTempFolderURLBMKey];
							success = !error;
							if (error)
							{
								NSLog(@"-verifyTempFolder- %@\n", error);
							}
						} else
						{
							[[NSUserDefaults standardUserDefaults] removeObjectForKey:kTempFolderURLBMKey];
							NSAlert *alert = [[NSAlert alloc] init];
							[alert setMessageText:@"Temporary Folder"];
							[alert setInformativeText:@"The temporary items folder was not selected. "
								"Restart the application then simply press Select."];
							[alert addButtonWithTitle:@"OK"];
							[alert setAlertStyle:NSAlertStyleWarning];
							[alert runModal];
						}
					}
				}
			}
		}
	}
#else
	BOOL	success = YES;
	NSURL* tempFolderURL = [[NSFileManager defaultManager] temporaryDirectory];
#endif
	if (success)
	{
		_tempFolderURL = tempFolderURL;
		tempFolderPathControl.URL = tempFolderURL;
	}
}

/****************************** verifyArduinoApp ******************************/
/*
*	This makes sure the previously selected Arduino app still exists.  If it no
*	longer exists the user will be asked to select one.
*/
- (void)verifyArduinoApp
{
#if SANDBOX_ENABLED
	NSURL*	arduinoAppURL = NULL;
	NSData*	arduinoAppURLBM = [[NSUserDefaults standardUserDefaults] objectForKey:kArduinoAppURLBMKey];
	if (arduinoAppURLBM)
	{
		arduinoAppURL = [NSURL URLByResolvingBookmarkData: arduinoAppURLBM
				options:NSURLBookmarkResolutionWithoutUI+NSURLBookmarkResolutionWithoutMounting+NSURLBookmarkResolutionWithSecurityScope
						relativeToURL:NULL bookmarkDataIsStale:NULL error:NULL];
	}
#else
	NSString*	arduinoAppPath = [[NSUserDefaults standardUserDefaults] objectForKey:kArduinoAppPathKey];
	NSURL*	arduinoAppURL = arduinoAppPath ? [NSURL fileURLWithPath:arduinoAppPath isDirectory:NO] : nil;
	if (arduinoAppURL)
	{
		arduinoPathControl.URL = arduinoAppURL;
	}
#endif
	if (!arduinoAppURL)
	{
		NSArray* appFolderURLs =[[NSFileManager defaultManager] URLsForDirectory:NSApplicationDirectory inDomains:NSLocalDomainMask];
		if ([appFolderURLs count] > 0)
		{
			//ArduinoAppOpenDelegate* arduinoAppOpenDelegate = [[ArduinoAppOpenDelegate alloc] init];
			_openTag = kArduinoPathControlTag;
			NSOpenPanel*	chooseAppPanel = [NSOpenPanel openPanel];
			if (chooseAppPanel)
			{
				[chooseAppPanel setCanChooseDirectories:NO];
				[chooseAppPanel setCanChooseFiles:YES];
				[chooseAppPanel setAllowsMultipleSelection:NO];
				chooseAppPanel.directoryURL = appFolderURLs[0];
				chooseAppPanel.delegate = self;
				chooseAppPanel.message = @"Locate the Arduino Application";
				chooseAppPanel.prompt = kSelectPrompt;
				if ([chooseAppPanel runModal] == NSModalResponseOK)
				{
#if SANDBOX_ENABLED
					arduinoAppURLBM = [[NSUserDefaults standardUserDefaults] objectForKey:kArduinoAppURLBMKey];
					arduinoAppURL = [NSURL URLByResolvingBookmarkData: arduinoAppURLBM
							options:NSURLBookmarkResolutionWithoutUI+NSURLBookmarkResolutionWithoutMounting+NSURLBookmarkResolutionWithSecurityScope
									relativeToURL:NULL bookmarkDataIsStale:NULL error:NULL];
#else
					NSString* arduinoAppPath = [[NSUserDefaults standardUserDefaults] objectForKey:kArduinoAppPathKey];
					arduinoAppURL = arduinoAppPath ? [NSURL fileURLWithPath:arduinoAppPath isDirectory:NO] : nil;
#endif
				}
			}
		}
	}
	_arduinoURL = arduinoAppURL;
	arduinoPathControl.URL = arduinoAppURL;
	
	// Log a warning if the arduino application isn't running.
	if (arduinoAppURL)
	{
		NSArray<NSRunningApplication *>*	runningApplications = [NSWorkspace sharedWorkspace].runningApplications;
		__block	BOOL	arduinoAppIsRunning = NO;
		[runningApplications enumerateObjectsUsingBlock:^(NSRunningApplication* inRunningApplication, NSUInteger inIndex, BOOL* outStop)
		{
			if (inRunningApplication.bundleIdentifier &&
				[inRunningApplication.bundleIdentifier compare:kArduinoBundleIdentifier] == 0 &&
				// Note that the path is used rather than isEqual of NSURL because
				// isEqual requires an exact match which may or may not account for
				// a missing trailing path delimiter.
				[inRunningApplication.bundleURL.path compare:_arduinoURL.path] == 0)
			{
				arduinoAppIsRunning = YES;
				*outStop = YES;
			}
		}];
		if (arduinoAppIsRunning == NO)
		{
			[_hexLoaderLogViewController postWarningString: @"The defined Arduino® App is not running."];
		}
	}
}

/**************************** verifyPackagesFolder ****************************/
/*
*	This makes sure the previous packages folder still exists.  If it no
*	longer exists the user will be asked to select it.
*/
- (void)verifyPackagesFolder
{
	BOOL	success = NO;
	NSURL*	packagesFolderURL = NULL;
	NSArray<NSURL*>* libraryFolderURLs =[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask];
	if (libraryFolderURLs.count > 0)
	{
#if SANDBOX_ENABLED
		// Kind of convoluted, but when you ask for the library folder in a sandboxed app you get the sandboxed folder
		// within the app's container.  To get the actual library folder you need to strip off 4 path components.
		// I know it's a kludge, but I don't know of an honest way of doing this.
		NSString*	packagesFolderPath = [[[[[[libraryFolderURLs objectAtIndex:0].path stringByDeletingLastPathComponent]
											stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
											stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Arduino15"];
		NSData*	packagesFolderURLBM = [[NSUserDefaults standardUserDefaults] objectForKey:kPackagesFolderURLBMKey];
		if (packagesFolderURLBM)
		{
			packagesFolderURL = [NSURL URLByResolvingBookmarkData: packagesFolderURLBM
					options:NSURLBookmarkResolutionWithoutUI+NSURLBookmarkResolutionWithoutMounting+NSURLBookmarkResolutionWithSecurityScope
							relativeToURL:NULL bookmarkDataIsStale:NULL error:NULL];
		}
		// stringByStandardizingPath will remove /private from the path. NSFileManager
		// seems to be standardizing the URL it returns.
		success = packagesFolderURL && [[packagesFolderURL.path stringByStandardizingPath] isEqualToString:packagesFolderPath];
		if (!success)
		{
			NSOpenPanel*	openPanel = [NSOpenPanel openPanel];
			if (openPanel)
			{
				[openPanel setCanChooseDirectories:YES];
				[openPanel setCanChooseFiles:NO];
				[openPanel setAllowsMultipleSelection:NO];
				openPanel.directoryURL = [NSURL fileURLWithPath:packagesFolderPath isDirectory:YES];
				openPanel.message = @"Because of sandbox issues, we need to get permission to access the Arduino15 folder. "
									"Please navigate to and select ~/Library/Arduino15.";
				openPanel.prompt = kSelectPrompt;
				//[openPanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result)
				{
					if ([openPanel runModal] == NSModalResponseOK)
					{
						NSArray* urls = [openPanel URLs];
						if ([urls count] == 1)
						{
							NSError*	error;
							packagesFolderURL = urls[0];
							if ([[packagesFolderURL.path stringByStandardizingPath] isEqualToString:packagesFolderPath])
							{
								packagesFolderURLBM = [packagesFolderURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
										includingResourceValuesForKeys:NULL relativeToURL:NULL error:&error];
								[[NSUserDefaults standardUserDefaults] setObject:packagesFolderURLBM forKey:kPackagesFolderURLBMKey];
								success = !error;
								if (error)
								{
									NSLog(@"-verifyPackagesFolder- %@\n", error);
								}
							} else
							{
								[[NSUserDefaults standardUserDefaults] removeObjectForKey:kPackagesFolderURLBMKey];
								NSAlert *alert = [[NSAlert alloc] init];
								[alert setMessageText:@"Arduino Packages Folder"];
								[alert setInformativeText:@"The Arduino15 packages folder was not selected. "
									"Restart the application then simply press Select."];
								[alert addButtonWithTitle:@"OK"];
								[alert setAlertStyle:NSAlertStyleWarning];
								[alert runModal];
							}
						}
					}
				}
			}
		}
#else
		NSString*	packagesFolderPath = [[libraryFolderURLs objectAtIndex:0].path stringByAppendingPathComponent:@"Arduino15"];
		packagesFolderURL = [NSURL fileURLWithPath:packagesFolderPath isDirectory:YES];
		success = YES;
#endif
	}
	if (success)
	{
		_packagesFolderURL = packagesFolderURL;
		packagesFolderPathControl.URL = packagesFolderURL;
	}
}

#pragma mark - MenuItem
/****************************** validateMenuItem ******************************/
- (BOOL)validateMenuItem:(NSMenuItem *)inMenuItem;
{
	BOOL	enableMenuItem;
	//fprintf(stderr, "validateMenuItem tag = %ld\n", inMenuItem.tag);
	switch (inMenuItem.tag)
	{
		case 91:	// Export selected items contextual menu item
		case 92:	// Dump selected items configuration(s) to log contextual menu item
		case 94:	// Export dump of elf object of each selected item contextual menu item
		case 11:	// File->Export menu item
		case 12:	// File->Export elf object menu item
			// Enable only when there is at least one row/sketch selected.
			enableMenuItem = _hexLoaderTableViewController.tableView.numberOfSelectedRows > 0;
			break;
		case kShowArduinoTempFolderTag:
			enableMenuItem = _hexLoaderTableViewController.tableView.numberOfSelectedRows == 1;
			break;
		default:
			enableMenuItem = YES;
			break;
	}
	return(enableMenuItem);
}

/********************************* exportHex **********************************/
- (IBAction)exportHex:(id)sender
{
	/*
	*
	*/
	BOOL	isDirectory;
	if (_exportFolderURL &&
		[[NSFileManager defaultManager] fileExistsAtPath:_exportFolderURL.path isDirectory:&isDirectory] &&
		isDirectory == YES)
	{
		NSIndexSet *selectedRows = _hexLoaderTableViewController.tableView.selectedRowIndexes;
		__block NSMutableArray<NSMutableDictionary*>*	sketches = _hexLoaderTableViewController.sketches;
		if (selectedRows.count)
		{
			[selectedRows enumerateIndexesUsingBlock:^(NSUInteger inIndex, BOOL *outStop)
			{
				NSMutableDictionary* sketchRec = [sketches objectAtIndex:inIndex];
				std::string	configText;
				[self configTextForSketch:sketchRec configText:configText];
				NSString*	configTextS = [NSString stringWithUTF8String:configText.c_str()];
				
				NSURL*	sourceHexFileURL = [((NSURL*)sketchRec[kTempURLKey]) URLByAppendingPathComponent:[sketchRec[kNameKey] stringByAppendingPathExtension:@"hex"]];
				NSURL*	configFileURL = [_exportFolderURL URLByAppendingPathComponent:[sketchRec[kNameKey] stringByAppendingPathExtension:@"txt"]];
				NSURL*	destFileURL = [_exportFolderURL URLByAppendingPathComponent:[sketchRec[kNameKey] stringByAppendingPathExtension:@"hex"]];
				[[NSFileManager defaultManager] removeItemAtURL:configFileURL error:nil];
				[[NSFileManager defaultManager] removeItemAtURL:destFileURL error:nil];
				BOOL success = [configTextS writeToURL:configFileURL atomically:NO encoding:NSUTF8StringEncoding error:nil] &&
							[[NSFileManager defaultManager] copyItemAtURL:sourceHexFileURL toURL:destFileURL error:nil];
				if (success)
				{
					[_hexLoaderLogViewController postInfoString: [NSString stringWithFormat:@"%@.hex has been copied to the Export folder.", sketchRec[kNameKey]]];
					[_hexLoaderLogViewController postInfoString: [NSString stringWithFormat:@"%@.txt has been created in the Export folder.", sketchRec[kNameKey]]];
				} else
				{
					[_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:@"Unable to export %@.", sketchRec[kNameKey]]];
				}
			}];
		} else
		{
			[_hexLoaderLogViewController postWarningString: @"No sketches selected."];
		}
	} else
	{
		[self logExportFolderIsUndefined];
	}
	
}

/********************************* dumpConfig *********************************/
- (IBAction)dumpConfig:(id)sender
{
	NSIndexSet *selectedRows = _hexLoaderTableViewController.tableView.selectedRowIndexes;
	__block NSMutableArray<NSMutableDictionary*>*	sketches = _hexLoaderTableViewController.sketches;
	if (selectedRows.count)
	{
		[selectedRows enumerateIndexesUsingBlock:^(NSUInteger inIndex, BOOL *outStop)
		{
			NSMutableDictionary* sketchRec = [sketches objectAtIndex:inIndex];
			std::string	configText;
			[self configTextForSketch:sketchRec configText:configText];
			[_hexLoaderLogViewController postInfoString:[NSString stringWithFormat:@"Config summary for %@", sketchRec[kNameKey]]];
			[[[[_hexLoaderLogViewController
				setColor:_hexLoaderLogViewController.blackColor]
				appendUTF8String:configText.c_str()]
				appendColoredString:_hexLoaderLogViewController.lightBlueColor string:@"----- end -----\n"] post];
		}];
	} else
	{
		[_hexLoaderLogViewController postWarningString: @"No sketches selected."];
	}
}

/**************************** configTextForSketch *****************************/
/*
*	When writing the config file exported with the hex file, some of the
*	key/values are from the AvrdudeConfigFile and the rest are selectively
*	loaded from the BoardsConfigFile.
*
*	To add more keys from the avrdude.conf file, modify the key list
*	at the top of AvrdudeConfigFile.cpp.
*
*	To add more keys from the BoardsConfigFile, make changes below.
*
*	Note that any additional keys you actually need to use in the HexLoader
*	sketch needs to be added to AVRConfig.cpp.
*/
- (void)configTextForSketch:(NSMutableDictionary*)inSketchRec configText:(std::string&)outConfigText
{
	NSString*	fqbnKey = inSketchRec[kFQBNKey];
	NSString*	deviceName = inSketchRec[kDeviceNameKey];
	if (fqbnKey &&
		deviceName)
	{
		std::string	avrdudeConfigPath;
		BoardsConfigFile*	configFile = _configFiles->GetConfigForFQBN(fqbnKey.UTF8String);
		uint32_t	keysNotFound = 0;
		if (configFile &&
			configFile->ValueForKey("config.path", avrdudeConfigPath, keysNotFound) &&
			keysNotFound == 0)
		{
			/*{
				std::string	configFileText;
				configFile->GetRootObject()->Write(0, configFileText);
				fprintf(stderr, "%s\n", configFileText.c_str());
			}*/
			AvrdudeConfigFile*	avrConfigFile = _avrdudeConfigFiles->GetConfigForPath(avrdudeConfigPath.c_str());
			if (avrConfigFile)
			{
				std::string devIDStr;
				avrConfigFile->IDForDesc(deviceName.UTF8String, true, devIDStr);
				JSONObject* devEntry = avrConfigFile->Export(deviceName.UTF8String);
				if (devEntry)
				{
					/*
					*	Remove:
					*		parent (only used by Export)
					*/
					devEntry->EraseElement("parent");
					/*
					*	Add:
					*		upload.speed
					*		upload.maximum_size
					*	Note that upload.maximum_size is flash.size - bootloader size
					*/
					std::string	valueStr;
					if (!configFile->RawValueForKey("upload.speed", valueStr))
					{
						valueStr.assign("0");
					}
					devEntry->InsertElement("upload.speed", new JSONString(valueStr));
					
					valueStr.clear();
					if (!configFile->RawValueForKey("upload.maximum_size", valueStr))
					{
						valueStr.assign("0");
					}
					devEntry->InsertElement("upload.maximum_size", new JSONString(valueStr));
					
					valueStr.clear();
					if (configFile->RawValueForKey("build.f_cpu", valueStr))
					{
						char f_cpuStr[15];
						snprintf(f_cpuStr, 15, "%d", atoi(valueStr.c_str()));
						valueStr.assign(f_cpuStr);
					} else
					{
						valueStr.assign("0");
					}
					devEntry->InsertElement("f_cpu", new JSONString(valueStr));
					
					{
						char byteCountStr[15];
						snprintf(byteCountStr, 15, "%d", ((NSNumber*)(inSketchRec[kLengthKey])).intValue);
						devEntry->InsertElement("byte_count", new JSONString(byteCountStr));
					}
					/*
					*	If this is the DCSensor...
					*/
					if ([(NSString*)(inSketchRec[kNameKey]) compare:@"DCSensor.ino"] == 0)
					{
						AVRElfFile	elfFile;
						if (elfFile.ReadFile([MainWindowController elfPathFor:inSketchRec forKey:kTempURLKey]))
						{
							/*
								The DCSensor.ino has a uint32_t unix timestamp created from the various time
								and date environment variables in gcc.  The unix timestamp needs to be
								unique for the DCSensor.ino because the CAN ID is initially created from it.
								 If the CAN ID is the same as another DCSensor on the bus, the bus may go
								into an error state. Because the Hex Loader copies the executable from an SD
								card, the timestamp is the same for every board.  This experiment extracts
								the address of the timestamp and dynamically replaces it while loading with
								the current timestamp.

								In order to do this the flash address of the timestamp needs to be
								determined. Normally the timestamp would be treated by the compiler as const
								and its value would be hard coded wherever it's used.  To keep this from
								happening the variable is marked as volitile.  This will force the
								initialization code to copy the initial value from flash to SRAM when the
								mcu boots.

								Calculating the flash address of the timestamp:  Find the symbol in the data
								section.  The address will be offset by the start of the data section.
								Example: if the data is initialized from flash (aka text) starting at 0x0C6E
								and the data section starts at 0x0060 in SRAM.  The initialization for the
								kTimestamp symbol at address 0x64 would be 0x0064 - 0x0060 + 0x0C6E = 0x0C72.
							*/
							const SSymbolTblEntry*	symTableEntry = nullptr;
							uint8_t*	symbolValuePtr = elfFile.GetSymbolValuePtr("kTimestamp", &symTableEntry);
							SSectEntry*	dataSect = elfFile.GetSectEntry(eData);
							SSectEntry*	textSect = elfFile.GetSectEntry(eText);
							if (symbolValuePtr && symbolValuePtr && dataSect && textSect)
							{
								uint32_t	timeStampAddr = textSect->addrInMem +
															textSect->size +
															symTableEntry->value -
															dataSect->addrInMem;
								/*
								*	Add this address to the AvrdudeConfig for this device.
								*/
								if (avrConfigFile)
								{
									char timeStampAddrStr[15];
									snprintf(timeStampAddrStr, 15, "0x%x", timeStampAddr);
									devEntry->InsertElement("timestamp", new JSONString(timeStampAddrStr));
								}
							}
						} else
						{
							[self->_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:
								@"Unable to open the %@.elf file and/or the elf file is damaged and/or this is not an AVR device.", inSketchRec[kNameKey]]];
						}
					}
					AvrdudeConfigFile::Write(devEntry, outConfigText);
				}
			}
		}
	}
}

/************************* logExportFolderIsUndefined *************************/
- (void)logExportFolderIsUndefined
{
	[_hexLoaderLogViewController postWarningString: @"The Export folder is undefined defined. "
		"Select \"Choose...\" from the Export Folder path popup."];
}

/******************************** exportElfObj ********************************/
- (IBAction)exportElfObj:(id)sender
{
	// build.export_path
	/*
	*
	*/
	BOOL	isDirectory;
	if (_exportFolderURL &&
		[[NSFileManager defaultManager] fileExistsAtPath:_exportFolderURL.path isDirectory:&isDirectory] &&
		isDirectory == YES)
	{
		NSIndexSet *selectedRows = _hexLoaderTableViewController.tableView.selectedRowIndexes;
		__block NSMutableArray<NSMutableDictionary*>*	sketches = _hexLoaderTableViewController.sketches;
		if (selectedRows.count)
		{
			[selectedRows enumerateIndexesUsingBlock:^(NSUInteger inIndex, BOOL *outStop)
			{
				NSMutableDictionary* sketchRec = [sketches objectAtIndex:inIndex];
				BoardsConfigFile*	configFile = _configFiles->GetConfigForFQBN(((NSString*)sketchRec[kFQBNKey]).UTF8String);
				if (configFile)
				{
					configFile->InsertKeyValue("build.path", ((NSURL*)sketchRec[kTempURLKey]).path.UTF8String);
					configFile->InsertKeyValue("build.project_name", ((NSString*)sketchRec[kNameKey]).UTF8String);
					configFile->InsertKeyValue("build.export_path", _exportFolderURL.path.UTF8String);
					//uint32_t	keysNotFound = 0;
					//std::string	value;
					//configFile->ValueForKey("recipe.elfdump.pattern", value, keysNotFound);
					//fprintf(stderr, "%s\n", value.c_str());
					if ([self runShellForRecipe:"recipe.elfdump.pattern" configFile:configFile])
					{
						[_hexLoaderLogViewController postInfoString: [NSString stringWithFormat:@"%@.elf.txt has been created in the Export folder.", sketchRec[kNameKey]]];
					} else
					{
						[_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:@"Unable to export dump of %@.elf to the Export folder.", sketchRec[kNameKey]]];
					}
				}
			}];
		} else
		{
			[_hexLoaderLogViewController postWarningString: @"No sketches selected."];
		}
	} else
	{
		[self logExportFolderIsUndefined];
	}
}

/********************************* logSuccess *********************************/
-(void)logSuccess
{
	[[_hexLoaderLogViewController appendColoredString:_hexLoaderLogViewController.greenColor string:@"Success!\n"] post];
}

/********************************** clear *************************************/
- (IBAction)clear:(id)sender
{
	[_hexLoaderLogViewController clear:sender];
}

/********************************* elfPathFor *********************************/
+(const char*)elfPathFor:(NSDictionary*)inSketchRec forKey:(NSString*)inKey
{
	return([((NSURL*)[inSketchRec objectForKey:inKey]) URLByAppendingPathComponent:[inSketchRec[kNameKey] stringByAppendingPathExtension:@"elf"]].path.UTF8String);
}


/***************************** runShellForRecipe ******************************/
- (BOOL)runShellForRecipe:(const char*)inRecipeKey configFile:(BoardsConfigFile*)inConfigFile
{
	BOOL		success = NO;
	std::string value;
	uint32_t keysNotFound = 0;
	inConfigFile->ValueForKey(inRecipeKey, value, keysNotFound);
	//fprintf(stderr, "keysNotFound = %d\n", keysNotFound);
	//fprintf(stderr, "%s\n", value.c_str());
	std::string escapedArguments;
	NSURL*	exeURL = [NSURL fileURLWithPath:@"/bin/bash"];
	NSArray<NSString*>* arguments = @[ @"-c", [NSString stringWithUTF8String:value.c_str()] ];
	NSTask* task = [[NSTask alloc] init];
	task.arguments = arguments;
	//[_multiAppLogViewController postInfoString:[NSString stringWithFormat:@"\"%@\" %@",exeURL.path, arguments]];
	task.executableURL = exeURL;
	__block NSString* taskOutputStr;
	__block NSString* taskErrorStr;
	task.standardOutput = [NSPipe pipe];
	task.standardError = [NSPipe pipe];
	task.terminationHandler = ^(NSTask* task)
	{
		NSData* taskOutput = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];
		taskOutputStr = [[NSString alloc] initWithData:taskOutput encoding:NSUTF8StringEncoding];
		NSData* taskError = [[task.standardError fileHandleForReading] readDataToEndOfFile];
		taskErrorStr = [[NSString alloc] initWithData:taskError encoding:NSUTF8StringEncoding];

		/*if (task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0)
		{
		}*/
	};
	@try
	{
		NSError *error = nil;
		
		success = [task launchAndReturnError:&error];
		[task waitUntilExit];
		if ([taskOutputStr length])
		{
			[self->_hexLoaderLogViewController postInfoString: [NSString stringWithFormat:@"%@\n", taskOutputStr]];
		}
		if ([taskErrorStr length])
		{
			success = NO;
			[self->_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:@"%@\n", taskErrorStr]];
		}
		if (!success)
		{
			NSLog(@"%@", error);
		}
	}
	@catch(NSException*	inException)
	{
		NSLog(@"%@", inException);
	}

	return(![task terminationStatus]);
}

/************************** initializeFQBNConfigFor ***************************/
/*
*	Using the fully qualified board name (FQBN), attempt to locate and initialize the
*	corresponding key values specific to this FQBN in the located boards.txt.
*	This creates a common/general configuration for the specific FQBN associated
*	with inSketchRec.  On subsequent calls, if a configuration for the FQBN has
*	already been created, the routine returns immediately.
*	When the configuration needs to be used for the specific sketch,
*	finalizeConfigFor is called.
*/
- (BoardsConfigFile*)initializeFQBNConfigFor:(NSDictionary*)inSketchRec configFile:(BoardsConfigFiles&)ioConfigFiles
{
	BoardsConfigFile*	configFile = NULL;
	NSURL*	tempURL = (NSURL*)[inSketchRec objectForKey:kTempURLKey];
	NSString*	sketchTempPath = tempURL.path;
	NSString*	sketchName = [inSketchRec objectForKey:kNameKey];
	FileInputBuffer		jsonFileInput([sketchTempPath stringByAppendingPathComponent:@"build.options.json"].UTF8String);
	JSONObject*			json = (JSONObject*)IJSONElement::Create(jsonFileInput);
	if (json &&
		json->GetType() == IJSONElement::eObject)
	{
		JSONString* customBuildProperties = (JSONString*)json->GetElement("customBuildProperties", IJSONElement::eString);
		JSONString* fqbn = (JSONString*)json->GetElement("fqbn", IJSONElement::eString);
		if (fqbn)
		{
			configFile = ioConfigFiles.GetConfigForFQBN(fqbn->GetString());
			if (!configFile)
			{
				configFile = new BoardsConfigFile(fqbn->GetString());
				ioConfigFiles.AdoptBoardsConfigFile(configFile);	// ioConfigFiles adopts/takes ownership of configFile
				//inConfigFile.SetFQBNFromString();
				/*
				*	Look through the hardware folders for the Boards.txt and Platform.txt for this FQBN.
				*/
				NSURL*	boardsTxtURL = nil;
				NSURL*	platformTxtURL = nil;
				NSString*	architecture = [NSString stringWithUTF8String:configFile->GetArchitecture().c_str()];
				JSONString* hardwareFolders = (JSONString*)json->GetElement("hardwareFolders", IJSONElement::eString);
				if (hardwareFolders)
				{
					StringInputBuffer	inputBuffer(hardwareFolders->GetString());
					std::string		hardwarePath;
					bool	morePaths = false;
					do
					{
						morePaths = inputBuffer.ReadTillChar(',', false, hardwarePath);
						inputBuffer++;
						hardwarePath += '/';
						hardwarePath.append(configFile->GetPackage());
						NSString*	packagePath = [NSString stringWithUTF8String:hardwarePath.c_str()];
						if ([[NSFileManager defaultManager] fileExistsAtPath:packagePath])
						{
							NSURL*	packageURL = [NSURL fileURLWithPath:packagePath isDirectory:YES];
							NSDirectoryEnumerator* directoryEnumerator =
								[[NSFileManager defaultManager] enumeratorAtURL:packageURL
									includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
										options:NSDirectoryEnumerationSkipsHiddenFiles
											errorHandler:nil];
							NSURL*	architectureURL = nil;
							for (NSURL* fileURL in directoryEnumerator)
							{
								NSNumber *isDirectory = nil;
								[fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

								if ([isDirectory boolValue])
								{
									NSString* name = nil;
									[fileURL getResourceValue:&name forKey:NSURLNameKey error:nil];

									if ([name isEqualToString:architecture])
									{
										architectureURL = fileURL;
										break;
									}
								}
							}
							if (architectureURL)
							{
								directoryEnumerator =
									[[NSFileManager defaultManager] enumeratorAtURL:architectureURL
										includingPropertiesForKeys:@[NSURLNameKey]
											options:NSDirectoryEnumerationSkipsHiddenFiles
												errorHandler:nil];
								for (NSURL* fileURL in directoryEnumerator)
								{
									NSString* name = nil;
									[fileURL getResourceValue:&name forKey:NSURLNameKey error:nil];
									if ([name isEqualToString:@"boards.txt"])
									{
										boardsTxtURL = fileURL;
										if (platformTxtURL)break;
									} else if ([name isEqualToString:@"platform.txt"])
									{
										platformTxtURL = fileURL;
										NSString* runtimePlatformDir = [fileURL.path stringByDeletingLastPathComponent];
										configFile->InsertKeyValue("runtime.platform.path", runtimePlatformDir.UTF8String);
										if (boardsTxtURL)break;
									}
								}
							}
							break;
						}
						hardwarePath.clear();
					} while(morePaths);
				}
				if (boardsTxtURL && platformTxtURL)
				{
					if (configFile->ReadFile(platformTxtURL.path.UTF8String, false) &&
							configFile->ReadFile(boardsTxtURL.path.UTF8String, true))
					{
						if (customBuildProperties)
						{
							configFile->ReadDelimitedKeyValuesFromString(customBuildProperties->GetString());
						}
						/*
						*	If the customBuildProperties didn't exist (very rare)
						*	or customBuildProperties doesn't contain the expected
						*	tools/avr keys THEN
						*	attempt to add them using the builtInToolsFolders object.
						*/
						std::string value;
						if (!configFile->RawValueForKey("runtime.tools.avr-gcc.path", value))
						{
							JSONString* toolsFolders = (JSONString*)json->GetElement("builtInToolsFolders", IJSONElement::eString);
							if (toolsFolders)
							{
								StringInputBuffer	inputBuffer(toolsFolders->GetString());
								for (uint8_t thisChar = inputBuffer.CurrChar(); thisChar; thisChar = inputBuffer.CurrChar())
								{
									inputBuffer.ReadTillChar(',', false, value);
									if (value.compare(value.length()-3, 3, "avr"))
									{
										value.clear();
										inputBuffer.NextChar();	// Skip the Delimiter
										continue;
									}
									configFile->InsertKeyValue("runtime.tools.avr-gcc.path", value);
									configFile->InsertKeyValue("runtime.tools.avrdude.path", value);
									break;
								}
							}
						}
						// If compiler.path is missing, THEN
						// add a default.
						if (!configFile->RawValueForKey("compiler.path", value))
						{
							configFile->InsertKeyValue("compiler.path", "{runtime.tools.avr-gcc.path}/bin/");
						}

						// Uncomment to dump the tree
						/*{
							std::string dumpString;
							configFile->GetRootObject()->Write(0, dumpString);
							fprintf(stderr, "\n\n%s\n", dumpString.c_str());
						}*/
					} else
					{
						configFile = NULL;
						[_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:@"Unable to load boards.txt and/or platform.txt for %@", sketchName]];
					}
				} else
				{
					[_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:@"Unable to locate boards.txt and/or platform.txt for %@", sketchName]];
				}
				if (configFile)
				{
					// For debugging
					configFile->InsertKeyValue("recipe.elfdump.pattern",
						"\"{compiler.path}avr-objdump\" -h -S -d -t -j .data -j .text -j .bss "
						"\"{build.path}/{build.project_name}.elf\" > "
						"\"{build.export_path}/{build.project_name}.elf.txt\"");
				}
			}
		}
	}
	return(configFile);
}

/********************************** doUpdate **********************************/
- (void)doUpdate
{
	__block BOOL	success = YES;
	__block NSMutableArray<NSMutableDictionary*>*	sketches = _hexLoaderTableViewController.sketches;
	if (sketches.count)
	{
		[sketches enumerateObjectsUsingBlock:
			^void(NSMutableDictionary* inSketchRec, NSUInteger inIndex, BOOL *outStop)
			{
				[inSketchRec removeObjectForKey:kTempURLKey];
			}];
	}

#if SANDBOX_ENABLED
	if (success &&
		[_tempFolderURL startAccessingSecurityScopedResource])
	{
#else
	if (success)
#endif
	{
		BOOL	tableNeedsReload = NO;
		// For each temporary arduino folder either update an existing sketch
		// entry in the table or add a new entry if one doesn't already exist.
		// Remove any sketch entries that no longer have a corresponding arduino
		// folder.
		{
			NSDirectoryEnumerator* tempFolderEnum = [[NSFileManager defaultManager] enumeratorAtURL:_tempFolderURL
				includingPropertiesForKeys:NULL options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
			NSURL* folderURL;
			[tempFolderEnum skipDescendants];
			while ((folderURL = [tempFolderEnum nextObject]))
			{
				if ([folderURL hasDirectoryPath])
				{
					if ([[folderURL lastPathComponent] hasPrefix: @"arduino_build_"])
					{
						/*
						*	Derive the sketch name by looking for the file that
						*	ends with ".ino.elf"
						*/
						NSDirectoryEnumerator* buildFolderEnum = [[NSFileManager defaultManager] enumeratorAtURL:folderURL
							includingPropertiesForKeys:NULL options:NSDirectoryEnumerationSkipsHiddenFiles |
								NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil];
						NSURL* fileURL;
						while ((fileURL = [buildFolderEnum nextObject]))
						{
							if ([fileURL.path hasSuffix:@".ino.elf"])
							{
								__block NSString*	sketchName = [[fileURL.path stringByDeletingPathExtension] lastPathComponent];
								//NSLog(@"\t%@", [folderURL.path lastPathComponent]);
								[sketches enumerateObjectsUsingBlock:
									^void(NSMutableDictionary* inSketchRec, NSUInteger inIndex, BOOL *outStop)
									{
										/*
										*	If this temporary folder is for this sketch...
										*/
										if ([inSketchRec[kNameKey] isEqualToString:sketchName])
										{
											/*
											*	If this sketch doesn't have a temporary folder URL OR
											*	this temporary folder is newer than the existing temporary folder THEN
											*	use this temporary folder.
											*
											*	This can happen when a sketch is closed and reopened within
											*	the Arduino IDE.
											*/
											if (![inSketchRec objectForKey:kTempURLKey] ||
												[[[NSFileManager defaultManager] attributesOfItemAtPath:((NSURL*)inSketchRec[kTempURLKey]).path error:nil].fileModificationDate compare:
												[[NSFileManager defaultManager] attributesOfItemAtPath:folderURL.path error:nil].fileModificationDate] < 0)
											{
												[inSketchRec setObject:folderURL forKey:kTempURLKey];
											}
											*outStop = YES;
											sketchName = nil;	// Set to nil to flag as already having a table entry.
										}
									}];
								/*
								*	If there is no table entry for this sketch THEN
								*	add it now.
								*/
								if (sketchName)
								{
									NSMutableDictionary* sketchRec = [NSMutableDictionary dictionaryWithCapacity:kNumTableColumns];
									[sketchRec setObject:[sketchName lastPathComponent] forKey:kNameKey];
									[sketchRec setObject:@"TBD" forKey:kIDKey];
									[sketchRec setObject:@"TBD" forKey:kSpeedKey];
									[sketchRec setObject:@"TBD" forKey:kBaudRateKey];
									[sketchRec setObject:@"TBD" forKey:kSignatureKey];
									[sketchRec setObject:[NSNumber numberWithInt:0] forKey:kLengthKey];
									[sketchRec setObject:@"TBD" forKey:kDeviceNameKey];
									[sketchRec setObject:folderURL forKey:kTempURLKey];
									[sketches addObject:sketchRec];
								}
							}
						}
					}
				}
			}
		}
		/*
		*	Remove any sketch table entries that no longer have a corresponding
		*	arduino build folder.
		*/
		{
			__block NSMutableIndexSet*	sketchesNotLocated = [NSMutableIndexSet indexSet];
			[sketches enumerateObjectsUsingBlock:
				^void(NSMutableDictionary* inSketchRec, NSUInteger inIndex, BOOL *outStop)
				{
					if ([inSketchRec objectForKey:kTempURLKey] == nil)
					{
						[sketchesNotLocated addIndex:inIndex];
					}
				}];
			if (sketchesNotLocated.count)
			{
				tableNeedsReload = YES;
				[sketches removeObjectsAtIndexes:sketchesNotLocated];
			}
		}
		if (sketches.count)
		{
			/*
			*	Create the configuration file(s) based on the FQBN(s)
			*	of each sketch.
			*/
			{
				AvrdudeConfigFile* avrConfigFile;
				NSMutableDictionary* sketchRec;
				NSUInteger	sketchCount = sketches.count;
				for (NSUInteger sketchIndex = 0; success && sketchIndex < sketchCount; sketchIndex++)
				{
					sketchRec = [sketches objectAtIndex:sketchIndex];
					// fileModificationDate
					if (_lastUpdate)
					{
						NSDictionary* folderAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:((NSURL*)sketchRec[kTempURLKey]).path error:nil];
						//NSLog(@"lastUpdate %@, modDate %@", _lastUpdate, folderAttrs.fileModificationDate);
						if (folderAttrs &&
							[_lastUpdate compare: folderAttrs.fileModificationDate] > 0)
						{
							continue;
						}
					}

					tableNeedsReload = YES;
					avrConfigFile = nullptr;
					BoardsConfigFile* configFile = [self initializeFQBNConfigFor:sketchRec configFile:*_configFiles];
					if (configFile)
					{
						[sketchRec setObject:[NSString stringWithUTF8String:configFile->GetFQBN().c_str()] forKey:kFQBNKey];
						std::string	speedStr;
						std::string	baudRateStr;
						std::string	deviceIDStr;
						std::string deviceName;
						std::string signatureStr;
						configFile->RawValueForKey("build.mcu", deviceName);
						//	std::string configContents;
						//	configFile->GetRootObject()->Write(0, configContents);
						//fprintf(stderr, "%s\n", configContents.c_str());
						//fprintf(stderr, "Updating %s\n", deviceName.c_str());
						std::string avrdudeConfigPath;
						if (!configFile->RawValueForKey("upload.speed", baudRateStr))
						{
							baudRateStr.assign("ICSP");
						}
						
						configFile->RawValueForKey("build.f_cpu", speedStr);
						
						/*
						*	Some tools.avrdude.config.path values refer to {path},
						*	but the only relevant path is at tools.avrdude.path,
						*	so promoting everything in tools.avrdude will result
						*	in tools.avrdude.path becoming path.  This has the
						*	side effect of changing tools.avrdude.config.path
						*	to config.path.
						*/
						configFile->Promote("tools.avrdude.");
						/*
						*	If there isn't a value for config.path THEN
						*	add a default value for "config.path" to this configFile...
						*/
						if (!configFile->RawValueForKey("config.path", avrdudeConfigPath))
						{
							configFile->InsertKeyValue("config.path", "{path}/etc/avrdude.conf");
						} else
						{
							avrdudeConfigPath.clear();
						}
						uint32_t	keysNotFound = 0;
						if (configFile->ValueForKey("config.path", avrdudeConfigPath, keysNotFound) &&
							keysNotFound == 0)
						{
							//fprintf(stderr, "%s\n", avrdudeConfigPath.c_str());
							avrConfigFile = _avrdudeConfigFiles->GetConfigForPath(avrdudeConfigPath.c_str());
							if (!avrConfigFile)
							{
								avrConfigFile = new AvrdudeConfigFile;
								if (avrConfigFile->ReadFile(avrdudeConfigPath.c_str()))
								{
									_avrdudeConfigFiles->AdoptAvrdudeConfigFile(avrdudeConfigPath, avrConfigFile);
								} else
								{
									[self->_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:
										@"Unable to open the avrdude.conf file for the device %s\n."
										"path = %s", deviceName.c_str(), avrdudeConfigPath.c_str()]];
									delete avrConfigFile;
									avrConfigFile = nullptr;
								}
							}
							if (avrConfigFile)
							{
								avrConfigFile->IDForDesc(deviceName, false, deviceIDStr);
								std::string	idKey(deviceIDStr);
								idKey+='.';
								JSONObject* entry = (JSONObject*)(avrConfigFile->GetRootObject()->GetElement(idKey, IJSONElement::eObject));
								if (entry)
								{
									JSONString*	signature = (JSONString*)(entry->GetElement("signature", IJSONElement::eString));
									if (signature)
									{
										signatureStr.assign(signature->GetString());
									}
								}
							}
						} else
						{
							[self->_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:
								@"Unable to locate the avrdude.conf file for the device %s\n.", deviceName.c_str()]];
						}
						/*
						*	Get the flash used
						*/
						{
							AVRElfFile	elfFile;
							if (elfFile.ReadFile([MainWindowController elfPathFor:sketchRec forKey:kTempURLKey]))
							{
								uint32_t	length = elfFile.GetFlashUsed();
								[sketchRec setObject:[NSNumber numberWithUnsignedLong:length] forKey:kLengthKey];
							} else
							{
								[self->_hexLoaderLogViewController postErrorString: [NSString stringWithFormat:
									@"Unable to open the %@.elf file and/or the elf file is damaged and/or this is not an AVR device.", sketchRec[kNameKey]]];
								success = NO;
							}
						}
						[sketchRec setObject:[NSString stringWithUTF8String:deviceName.c_str()] forKey:kDeviceNameKey];
						[sketchRec setObject:[NSString stringWithUTF8String:deviceIDStr.c_str()] forKey:kIDKey];
						[sketchRec setObject:[NSString stringWithUTF8String:baudRateStr.c_str()] forKey:kBaudRateKey];
						if (speedStr.length() > 1)
						{
							double speed = (double)(atoi(speedStr.c_str()))/1000000;
							[sketchRec setObject:[NSString stringWithFormat:@"%gMHz", speed] forKey:kSpeedKey];
						}
						if (signatureStr.length() == 8)
						{
							[sketchRec setObject:[NSString stringWithFormat:@"%.2s %.2s %.2s", &signatureStr.c_str()[2], &signatureStr.c_str()[4], &signatureStr.c_str()[6]] forKey:kSignatureKey];
						}
						continue;
					}
					success = NO;
				}
			}
		}
#if SANDBOX_ENABLED
		[_tempFolderURL stopAccessingSecurityScopedResource];
#endif
		if (tableNeedsReload)
		{
			[_hexLoaderTableViewController.tableView reloadData];
		}
		_lastUpdate = [NSDate date];
	} else if (success) // if success but no access to temp folder
	{
		success = NO;
		//[_hexLoaderLogViewController postErrorString: @"Unable to access the temporary items folder (sandbox issue.)"];
	}
}

@end
