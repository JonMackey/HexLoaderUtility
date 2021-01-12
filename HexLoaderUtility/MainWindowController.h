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
//  MainWindowController.h
//  HexLoaderUtility
//
//  Created by Jon on 10/20/2020.
//  Copyright © 2020 Jon Mackey. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "HexLoaderUtilityLogViewController.h"
#import "HexLoaderUtilityTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MainWindowController : NSWindowController <NSUserNotificationCenterDelegate,
													NSPathControlDelegate, NSMenuItemValidation,
													NSOpenSavePanelDelegate>
{
	IBOutlet NSView *sketchesView;
	IBOutlet NSView *serialView;
	IBOutlet NSPathControl *arduinoPathControl;
	IBOutlet NSPathControl *tempFolderPathControl;
	IBOutlet NSPathControl *packagesFolderPathControl;
	IBOutlet NSPathControl *exportFolderPathControl;
}
//- (IBAction)open:(id)sender;
//- (IBAction)add:(id)sender;
//- (IBAction)save:(id)sender;
//- (IBAction)saveas:(id)sender;
- (IBAction)update:(id)sender;
- (IBAction)exportHex:(id)sender;

@property (nonatomic, strong) NSURL *arduinoURL;
@property (nonatomic, strong) NSURL *tempFolderURL;
@property (nonatomic, strong) NSURL *packagesFolderURL;
@property (nonatomic, strong) NSURL *exportFolderURL;
@property (nonatomic, strong) HexLoaderUtilityLogViewController *hexLoaderLogViewController;
@property (nonatomic, strong) HexLoaderUtilityTableViewController *hexLoaderTableViewController;
@property (nonatomic, strong) NSTimer* updateTimer;
@property (nonatomic, strong) NSDate* lastUpdate;
@property (nonatomic) NSUInteger openTag;

//- (void)doOpen:(NSURL*)inDocURL;

@end

NS_ASSUME_NONNULL_END
