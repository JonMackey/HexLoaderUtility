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
//  HexLoaderUtilityTableViewController.m
//  HexLoaderUtility
//
//  Created by Jon on 10/20/2020.
//  Copyright © 2020 Jon Mackey. All rights reserved.
//

#import "HexLoaderUtilityTableViewController.h"

@interface HexLoaderUtilityTableViewController ()

@end

@implementation HexLoaderUtilityTableViewController

NSUInteger const kNumTableColumns = 9;
NSString *const kNameKey = @"name";
NSString *const kIDKey = @"id";
NSString *const kSpeedKey = @"speed";
NSString *const kBaudRateKey = @"baudRate";
NSString *const kSignatureKey = @"signature";
NSString *const kLengthKey = @"length";
NSString *const kDeviceNameKey = @"deviceName";
NSString *const kTempURLKey = @"tempURL";
#if SANDBOX_ENABLED
NSString *const kSourceBMKey = @"sourceBM";
#else
NSString *const kSourcePathKey = @"sourcePath";
#endif
NSString *const kRowPasteboardType = @"kRowPasteboardType";

/****************************** setTempFolderURL ******************************/
- (void)setTempFolderURL:(NSURL*)inTempFolderURL
{
	_tempFolderURL = inTempFolderURL;
	if (inTempFolderURL)
	{
 		// Receive notification of changes to the temporary items folder...
        [NSFileCoordinator addFilePresenter:self];
	}
}

/*************************** presentedItemDidChange ***************************/
- (void)presentedItemDidChange
{
	_tempFolderChanged = YES;
}

/****************************** presentedItemURL ******************************/
- (NSURL *)presentedItemURL
{
	return(_tempFolderURL);
}

/************************* presentedItemOperationQueue ************************/
- (NSOperationQueue *)presentedItemOperationQueue
{
	return(NSOperationQueue.mainQueue);
}

/****************************** viewWillDisappear *****************************/
- (void)viewWillDisappear
{
 	if (_tempFolderURL)
 	{
 		// Remove notification of changes to the temporary items folder...
		[NSFileCoordinator removeFilePresenter:self];
		//NSLog(@"removeFilePresenter\n");
	}
}

/****************************** viewDidLoad ***********************************/
- (void)viewDidLoad
{
    [super viewDidLoad];
	//[_tableView registerForDraggedTypes:[NSArray arrayWithObjects: NSPasteboardTypeFileURL, kRowPasteboardType, nil]];
   	self.sketches = [NSMutableArray array];
   	//self.sketches = [NSMutableArray arrayWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"DummyFiles" withExtension:@"plist"]];
		//[_tableView registerForDraggedTypes:[NSArray arrayWithObjects:[self.arrayController entityName], nil]];

	//[_tableView setDraggingDestinationFeedbackStyle:NSTableViewDraggingDestinationFeedbackStyleRegular];
	

}

/********************************* showInFinder *******************************/
/*- (IBAction)showSketchInFinder:(id)sender
{

}*/


/************************** checkForTempFolderChanges *************************/
- (void)checkForTempFolderChanges:(NSTimer *)inTimer
{
	if (_tempFolderChanged)
	{
		_tempFolderChanged = NO;
		//NSLog(@"_tempFolderChanged\n");
	}
}

/********************************* keyDown ************************************/
- (void)keyDown:(NSEvent *)inEvent
{
    // Arrow keys are associated with the numeric keypad
    /*fprintf(stderr, "NSEventModifierFlagNumericPad = 0x%X\n", (int)NSEventModifierFlagNumericPad);
    fprintf(stderr, "NSEventModifierFlagFunction = 0x%X\n", (int)NSEventModifierFlagFunction);
    fprintf(stderr, "NSEventModifierFlagFunction = 0x%X, keyCode =0x%hX\n", (int)inEvent.modifierFlags, inEvent.keyCode);*/
    if ([inEvent modifierFlags] == 0x100 &&
    	[inEvent keyCode] == 0x33)
	{
	//	[self removeSelection:self];
	} else
	{
		[super keyDown:inEvent];
	}
}

/***************************** setSketches *********************************/
-(void)setSketches:(NSMutableArray<NSMutableDictionary *> *)sketches
{
	_sketches = sketches;
    [self.tableView reloadData];
}

#if 0
// Not relevant for this app
/***************************** removeSelection ********************************/
- (IBAction)removeSelection:(id)sender
{
	NSIndexSet *selection = self.tableView.selectedRowIndexes;
	[self.sketches removeObjectsAtIndexes:selection];
    [self.tableView reloadData];
}
#endif
/************************ numberOfRowsInTableView *****************************/
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	//fprintf(stderr, "numberOfRowsInTableView = %d\n", (int)self.sketches.count);
    return(self.sketches != NULL ? self.sketches.count : 0);
}

/******************************* tableView ************************************/
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTextField *textField = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
	textField.objectValue = _sketches[row][textField.placeholderString];
    return textField;
}

#if 0
/********************* stringByAbbreviatingWithTildeInPath ********************/
/*
*	Cleans up inPath to use a tilda rather than the username.
*	NSString's stringByAbbreviatingWithTildeInPath doesn't work for sandboxed
*	applications because the home directory of a sandboxed app
*	includes the container rather than /Users/un/...  (or maybe it does work,
*	just not how I'd like it to.)
*/
- (NSString*)stringByAbbreviatingWithTildeInPath:inPath
{
	NSArray* homePathComponents = [NSHomeDirectory() pathComponents];
	if (homePathComponents.count >= 3)
	{
		NSString* homePath = [NSString pathWithComponents:[NSArray arrayWithObjects:[homePathComponents objectAtIndex:0], [homePathComponents objectAtIndex:1], [homePathComponents objectAtIndex:2], nil]];
		if ([inPath hasPrefix:homePath])
		{
			inPath = [NSString stringWithFormat:@"~%@", [inPath substringFromIndex:homePath.length]];
		}
	}
	return(inPath);
}
/******************************* clearTable ***********************************/
- (void)clearTable
{
	[self.sketches removeAllObjects];
	[self.tableView reloadData];
}

/******************************** addFile *************************************/
- (BOOL)addFile:(NSURL*)inFileURL
{
	return([self insertFile:inFileURL atIndex:-1]);
}
#endif

/**************************** handleDoubleClick *******************************/
- (IBAction)handleDoubleClick:(id)sender
{
	fprintf(stderr, "double click in row %ld\n", _tableView.clickedRow);
}

#if 0
/******************************* insertFile ***********************************/
- (BOOL)insertFile:(NSURL*)inFileURL atIndex:(NSInteger)inRow
{
	/*
	*	If a directory was dropped, assume the user wants to add the sketch
	*	within the folder of the same name.
	*/
	if ([inFileURL hasDirectoryPath])
	{
		inFileURL = [[NSURL URLWithString:[[inFileURL.path lastPathComponent] stringByAppendingPathExtension:@"ino"] relativeToURL:inFileURL] absoluteURL];
		if (![inFileURL checkResourceIsReachableAndReturnError:nil])
		{
			inFileURL = nil;
		}
	}
	
	if (inFileURL)
	{
		NSString* filePath = [inFileURL path];
		if ([[filePath pathExtension] isEqualToString:@"ino"])
		{
			NSString*	name = filePath.lastPathComponent;
			NSUInteger index = [self.sketches indexOfObjectPassingTest:
				^BOOL(NSMutableDictionary* inFileRec, NSUInteger inIndex, BOOL *outStop)
				{
					*outStop = [inFileRec[kNameKey] isEqualToString:name];
					return (*outStop);
				}];
			if (index == NSNotFound)
			{
				NSError*	error = nil;
#if SANDBOX_ENABLED
				NSData*	sourceBM = [inFileURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope+NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess
								includingResourceValuesForKeys:NULL relativeToURL:NULL error:&error];
				if (!error)
				{
					NSNumber*	zeroNum = [NSNumber numberWithUnsignedShort:0];
					NSMutableDictionary* newItem = [NSMutableDictionary dictionaryWithObjectsAndKeys:name, kNameKey,
												zeroNum, kIDKey, zeroNum, kLengthKey,
													@"TBD", kDeviceNameKey, sourceBM, kSourceBMKey, nil];
#else
				{
					NSNumber*	zeroNum = [NSNumber numberWithUnsignedShort:0];
					NSMutableDictionary* newItem = [NSMutableDictionary dictionaryWithObjectsAndKeys:name, kNameKey,
												@"id", kIDKey, zeroNum, kLengthKey,
													@"TBD", kDeviceNameKey, inFileURL.path, kSourcePathKey, nil];
#endif
					if (inRow < 0)
					{
						[self.sketches addObject:newItem];
					} else
					{
						[self.sketches insertObject:newItem atIndex:inRow];
					}
					[self.tableView reloadData];
				}
				
				return (!error);
			}
		}
	}
	return (NO);
}

/****************************** validateDrop **********************************/
- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)sender proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
	//fprintf(stderr, "validateDrop, proposedDropOperation = %lu\n",(unsigned long)dropOperation);

	//Destination is self
	if ([sender draggingSource] == tableView)
	{
		//fprintf(stderr, "destination is self, and row is %li",(long)row);

		return NSDragOperationMove;
	}
	return NSDragOperationLink;
}

/*************************** writeRowsWithIndexes *****************************/
- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard
{
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes requiringSecureCoding:NO error:nil];
    [pasteboard declareTypes:[NSArray arrayWithObject:kRowPasteboardType] owner:self];
    [pasteboard setData:data forType:kRowPasteboardType];
    return [rowIndexes count] > 0;
}

/*********************** writeSketchesToURL *************************/
- (BOOL)writeSketchesToURL:(NSURL*)inDocURL
{
	BOOL success = NO;
	if (inDocURL)
	{
#if SANDBOX_ENABLED
		[inDocURL startAccessingSecurityScopedResource];
		__block NSMutableArray* sketchesToArchive = [NSMutableArray array];
		[_sketches enumerateObjectsUsingBlock:
			^void(NSMutableDictionary* inSketchRec, NSUInteger inIndex, BOOL *outStop)
			{
				[sketchesToArchive addObject:[inSketchRec objectForKey:kSourceBMKey]];
			}];
		NSData* archivedData = [NSKeyedArchiver archivedDataWithRootObject:sketchesToArchive requiringSecureCoding:NO error:nil];
		success = [archivedData writeToURL:inDocURL atomically:NO];
		[inDocURL stopAccessingSecurityScopedResource];
#else
		__block NSMutableArray* sketchesToArchive = [NSMutableArray array];
		[_sketches enumerateObjectsUsingBlock:
			^void(NSMutableDictionary* inSketchRec, NSUInteger inIndex, BOOL *outStop)
			{
				[sketchesToArchive addObject:[inSketchRec objectForKey:kSourcePathKey]];
			}];
		NSData* archivedData = [NSKeyedArchiver archivedDataWithRootObject:sketchesToArchive requiringSecureCoding:NO error:nil];
		success = [archivedData writeToURL:inDocURL atomically:NO];
#endif
	}
	return(success);
}

/*********************** setSketchesWithContentsOfURL *************************/
- (BOOL)setSketchesWithContentsOfURL:(NSURL*)inDocURL
{
	BOOL success = NO;
	if (inDocURL)
	{
		NSError*	error = nil;
#if SANDBOX_ENABLED
		[inDocURL startAccessingSecurityScopedResource];
		NSData* archivedData = [NSData dataWithContentsOfURL:inDocURL];
		//NSArray* archivedSketches = [NSKeyedUnarchiver unarchiveObjectWithData:archivedData]; << depreciated
		NSSet* classes = [NSSet setWithObjects:[NSArray class], [NSData class], nil];
		NSMutableArray* archivedSketches = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:archivedData error:&error];
		[inDocURL stopAccessingSecurityScopedResource];
#else
		NSData* archivedData = [NSData dataWithContentsOfURL:inDocURL];
		NSSet* classes = [NSSet setWithObjects:[NSArray class], [NSString class], nil];
		NSMutableArray* archivedSketches = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:archivedData error:&error];
#endif
		if (error)
		{
			NSLog(@"%@", error);
		}
		if (archivedSketches)
		{
			__block NSMutableArray<NSMutableDictionary*>* sketches = [NSMutableArray array];
#if SANDBOX_ENABLED
			[archivedSketches enumerateObjectsUsingBlock:
				^void(NSData* inSketchBM, NSUInteger inIndex, BOOL *outStop)
				{
					NSURL*	sketchURL = [NSURL URLByResolvingBookmarkData:
							inSketchBM
								options:NSURLBookmarkResolutionWithoutUI+NSURLBookmarkResolutionWithoutMounting+NSURLBookmarkResolutionWithSecurityScope
									relativeToURL:NULL bookmarkDataIsStale:NULL error:NULL];
					if ([[[sketchURL.path lastPathComponent] pathExtension] isEqualToString:@"ino"])
					{
						NSMutableDictionary* sketchRec = [NSMutableDictionary dictionaryWithCapacity:5];
						[sketchRec setObject:[sketchURL.path lastPathComponent] forKey:kNameKey];
						[sketchRec setObject:@"id" forKey:kIDKey];
						[sketchRec setObject:[NSNumber numberWithInt:0] forKey:kLengthKey];
						[sketchRec setObject:@"TBD" forKey:kDeviceNameKey];
						[sketchRec setObject:inSketchBM forKey:kSourceBMKey];
						[sketches addObject:sketchRec];
					}
				}];
#else
			[archivedSketches enumerateObjectsUsingBlock:
				^void(NSString* inSketchPath, NSUInteger inIndex, BOOL *outStop)
				{
					if ([[[inSketchPath lastPathComponent] pathExtension] isEqualToString:@"ino"])
					{
						NSMutableDictionary* sketchRec = [NSMutableDictionary dictionaryWithCapacity:5];
						[sketchRec setObject:[inSketchPath lastPathComponent] forKey:kNameKey];
						[sketchRec setObject:@"id" forKey:kIDKey];
						[sketchRec setObject:[NSNumber numberWithInt:0] forKey:kLengthKey];
						[sketchRec setObject:@"TBD" forKey:kDeviceNameKey];
						[sketchRec setObject:inSketchPath forKey:kSourcePathKey];
						[sketches addObject:sketchRec];
					}
				}];
#endif
			if (sketches.count)
			{
				success = YES;
				[self setSketches:sketches];
			}
		}
	}
	return(success);
}
#endif
@end
