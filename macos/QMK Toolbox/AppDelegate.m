//
//  AppDelegate.m
//  qmk_toolbox
//
//  Created by Jack Humbert on 9/3/17.
//  Copyright © 2017 Jack Humbert. This code is licensed under MIT license (see LICENSE.md for details).
//

#import "AppDelegate.h"

#import "Constants.h"
#import "Flashing.h"
#import "HIDConsoleListener.h"
#import "QMKWindow.h"
#import "USB.h"

@interface AppDelegate () <NSTextViewDelegate, NSComboBoxDelegate, HIDConsoleListenerDelegate, FlashingDelegate, USBDelegate>

@property (weak) IBOutlet QMKWindow *window;
@property IBOutlet NSTextView * textView;
@property IBOutlet NSMenuItem * clearMenuItem;
@property IBOutlet NSComboBox * filepathBox;
@property IBOutlet NSButton * openButton;
@property IBOutlet NSComboBox * mcuBox;
@property IBOutlet NSButton * flashButton;
@property IBOutlet NSButton * resetButton;
@property IBOutlet NSButton * clearEEPROMButton;
@property IBOutlet NSComboBox * keyboardBox;
@property IBOutlet NSComboBox * keymapBox;
@property IBOutlet NSButton * loadButton;
@property IBOutlet NSComboBox * consoleListBox;

@property Flashing * flasher;

@property HIDConsoleListener * consoleListener;

@property HIDConsoleDevice * lastReportedDevice;
@end

@implementation AppDelegate

@synthesize canFlash;
@synthesize canReset;
@synthesize canClearEEPROM;

- (BOOL) autoFlashEnabled {
    return _autoFlashEnabled;
}

- (void)setAutoFlashEnabled:(BOOL)autoFlashEnabled {
    _autoFlashEnabled = autoFlashEnabled;
    if (autoFlashEnabled) {
        [_printer print:@"Auto-flash enabled" withType:MessageType_Info];
        [self disableUI];
    } else {
        [_printer print:@"Auto-flash disabled" withType:MessageType_Info];
        [self enableUI];
    }
}

- (IBAction) openButtonClick:(id) sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:@"Select firmware to load"];
    NSArray* types = @[@"qmk", @"bin", @"hex"];
    [panel setAllowedFileTypes:types];

    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            [self setFilePath:[[panel URLs] objectAtIndex:0]];
        }
    }];
}

- (IBAction) flashButtonClick:(id) sender {
    if ([USB areDevicesAvailable]) {
        int error = 0;
        if ([[_mcuBox objectValue] isEqualToString:@""]) {
            [_printer print:@"Please select a microcontroller" withType:MessageType_Error];
            error++;
        }
        if ([[_filepathBox objectValue] isEqualToString:@""]) {
            [_printer print:@"Please select a file" withType:MessageType_Error];
            error++;
        }
        if (error == 0) {
            if (!self.autoFlashEnabled) {
                [self disableUI];
            }

            [_printer print:@"Attempting to flash, please don't remove device" withType:MessageType_Bootloader];
            // this is dumb, but the delay is required to let the previous print command show up
            double delayInSeconds = .01;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                [self.flasher performSelector:@selector(flash:withFile:) withObject:[self.mcuBox objectValue] withObject:[self.filepathBox objectValue]];
            });

            if (!self.autoFlashEnabled) {
                [self enableUI];
            }
        }
    } else {
        [_printer print:@"There are no devices available" withType:MessageType_Error];
    }
}

- (IBAction) resetButtonClick:(id) sender {
    if ([[_mcuBox objectValue] isEqualToString:@""]) {
        [_printer print:@"Please select a microcontroller" withType:MessageType_Error];
    } else {
        if (!self.autoFlashEnabled) {
            [self disableUI];
        }

        [_flasher reset:(NSString *)[_mcuBox objectValue]];

        if (!self.autoFlashEnabled) {
            [self enableUI];
        }
    }
}

- (IBAction) clearEEPROMButtonClick:(id) sender {
    if ([[_mcuBox objectValue] isEqualToString:@""]) {
        [_printer print:@"Please select a microcontroller" withType:MessageType_Error];
    } else {
        if (!self.autoFlashEnabled) {
            [self disableUI];
        }

        [_flasher clearEEPROM:(NSString *)[_mcuBox objectValue]];

        if (!self.autoFlashEnabled) {
            [self enableUI];
        }
    }
}

- (IBAction) setHandednessButtonClick:(id) sender {
    if ([[_mcuBox objectValue] isEqualToString:@""]) {
        [_printer print:@"Please select a microcontroller" withType:MessageType_Error];
    } else {
        if (!self.autoFlashEnabled) {
            [self disableUI];
        }

        [_flasher setHandedness:(NSString *)[_mcuBox objectValue] rightHand:[sender tag] == 1];

        if (!self.autoFlashEnabled) {
            [self enableUI];
        }
    }
}

- (void)setSerialPort:(NSString *)port {
    _flasher.serialPort = port;
}

- (void)setMountPoint:(NSString *)mountPoint {
    _flasher.mountPoint = mountPoint;
}

- (void)deviceConnected:(Chipset)chipset {
    if (self.autoFlashEnabled) {
        [self flashButtonClick:NULL];
    }
    [self enableUI];
}

- (void)deviceDisconnected:(Chipset)chipset {
    [self enableUI];
}

- (void)disableUI {
    self.canFlash = NO;
    self.canReset = NO;
    self.canClearEEPROM = NO;
}

- (void)enableUI {
    self.canFlash = [_flasher canFlash];
    self.canReset = [_flasher canReset];
    self.canClearEEPROM = [_flasher canClearEEPROM];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if ([[[filename pathExtension] lowercaseString] isEqualToString:@"qmk"] ||
    [[[filename pathExtension] lowercaseString] isEqualToString:@"hex"] ||
    [[[filename pathExtension] lowercaseString] isEqualToString:@"bin"]) {
        [self setFilePath:[NSURL fileURLWithPath:filename]];
        return true;
    } else {
        return false;
    }
}

- (IBAction)updateFilePath:(id)sender {
    if (![[_filepathBox objectValue] isEqualToString:@""])
        [self setFilePath:[NSURL URLWithString:[_filepathBox objectValue]]];
}

- (void)setFilePath:(NSURL *)path {
    NSString * filename = @"";
    if ([path.scheme isEqualToString:@"file"])
        filename = [[path.absoluteString stringByRemovingPercentEncoding] stringByReplacingOccurrencesOfString:@"file://" withString:@""];
    if ([path.scheme isEqualToString:@"qmk"]) {
        NSURL * url;
        if ([path.absoluteString containsString:@"qmk://"])
            url = [NSURL URLWithString:[path.absoluteString stringByReplacingOccurrencesOfString:@"qmk://" withString:@""]];
        else
            url = [NSURL URLWithString:[path.absoluteString stringByReplacingOccurrencesOfString:@"qmk:" withString:@""]];

        [_printer print:[NSString stringWithFormat:@"Downloading the file: %@", url.absoluteString] withType:MessageType_Info];
        NSData * data = [NSData dataWithContentsOfURL:url];
        if (!data) {
            // Try .bin extension if .hex 404'd
            url = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"bin"];
            [_printer print:[NSString stringWithFormat:@"No .hex file found, trying %@", url.absoluteString] withType:MessageType_Info];
            data = [NSData dataWithContentsOfURL:url];
        }
        if (data) {
            NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
            NSString * downloadsDirectory = [paths objectAtIndex:0];
            NSString * name = [url.lastPathComponent stringByReplacingOccurrencesOfString:@"." withString:[NSString stringWithFormat:@"_%@.", [[[NSProcessInfo processInfo] globallyUniqueString] substringToIndex:8]]];
            filename = [NSString stringWithFormat:@"%@/%@", downloadsDirectory, name];
            [data writeToFile:filename atomically:YES];
            [_printer printResponse:[NSString stringWithFormat:@"File saved to: %@", filename] withType:MessageType_Info];
        }
    }
    if (![filename isEqualToString:@""]) {
        if ([_filepathBox indexOfItemWithObjectValue:filename] == NSNotFound)
            [_filepathBox addItemWithObjectValue:filename];
        [_filepathBox selectItemWithObjectValue:filename];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[[NSURL alloc] initFileURLWithPath:filename]];
    }
}

- (BOOL)readFromURL:(NSURL *)inAbsoluteURL ofType:(NSString *)inTypeName error:(NSError **)outError {
    [self setFilePath:inAbsoluteURL];
    return YES;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
    [appleEventManager setEventHandler:self andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply
{
    [self setFilePath:[NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [_window setup];

    _printer = [[Printing alloc] initWithTextView:_textView];
    _flasher = [[Flashing alloc] initWithPrinter:_printer];
    _flasher.delegate = self;

    [[_textView menu] addItem: [NSMenuItem separatorItem]];
    [[_textView menu] addItem: _clearMenuItem];

    [self loadMicrocontrollers];
    [self loadKeyboards];
    [self loadRecentDocuments];

    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    [_printer print:[NSString stringWithFormat:@"QMK Toolbox %@ (http://qmk.fm/toolbox)", version] withType:MessageType_Info];
    [_printer printResponse:@"Supported bootloaders:\n" withType:MessageType_Info];
    [_printer printResponse:@" - ARM DFU (APM32, Kiibohd, STM32, STM32duino) via dfu-util (http://dfu-util.sourceforge.net/)\n" withType:MessageType_Info];
    [_printer printResponse:@" - Atmel/LUFA/QMK DFU via dfu-programmer (http://dfu-programmer.github.io/)\n" withType:MessageType_Info];
    [_printer printResponse:@" - Atmel SAM-BA (Massdrop) via Massdrop Loader (https://github.com/massdrop/mdloader)\n" withType:MessageType_Info];
    [_printer printResponse:@" - BootloadHID (Atmel, PS2AVRGB) via bootloadHID (https://www.obdev.at/products/vusb/bootloadhid.html)\n" withType:MessageType_Info];
    [_printer printResponse:@" - Caterina (Arduino, Pro Micro) via avrdude (http://nongnu.org/avrdude/)\n" withType:MessageType_Info];
    [_printer printResponse:@" - HalfKay (Teensy, Ergodox EZ) via Teensy Loader (https://pjrc.com/teensy/loader_cli.html)\n" withType:MessageType_Info];
    [_printer printResponse:@" - LUFA Mass Storage\n" withType:MessageType_Info];
    [_printer printResponse:@"Supported ISP flashers:\n" withType:MessageType_Info];
    [_printer printResponse:@" - AVRISP (Arduino ISP)\n" withType:MessageType_Info];
    [_printer printResponse:@" - USBasp (AVR ISP)\n" withType:MessageType_Info];
    [_printer printResponse:@" - USBTiny (AVR Pocket)\n" withType:MessageType_Info];

    self.consoleListener = [[HIDConsoleListener alloc] init];
    self.consoleListener.delegate = self;
    [self.consoleListener start];

    [USB setupWithPrinter:_printer andDelegate:self];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mcuSelectionChanged) name:NSComboBoxSelectionDidChangeNotification object:_mcuBox];
}

- (void)consoleDeviceDidConnect:(HIDConsoleDevice *)device {
    self.lastReportedDevice = device;
    [self updateConsoleList];
    NSString * deviceConnectedString = [NSString stringWithFormat:@"HID console connected: %@", device];
    [_printer print:deviceConnectedString withType:MessageType_HID];
}

- (void)consoleDeviceDidDisconnect:(HIDConsoleDevice *)device {
    self.lastReportedDevice = nil;
    [self updateConsoleList];
    NSString * deviceDisconnectedString = [NSString stringWithFormat:@"HID console disconnected: %@", device];
    [_printer print:deviceDisconnectedString withType:MessageType_HID];
}

- (void)consoleDevice:(HIDConsoleDevice *)device didReceiveReport:(NSString *)report {
    NSInteger selectedDevice = [self.consoleListBox indexOfSelectedItem];
    if (selectedDevice == 0 || self.consoleListener.devices[selectedDevice - 1] == device) {
        if (self.lastReportedDevice != device) {
             [_printer print:[NSString stringWithFormat:@"%@ %@:", device.manufacturerString, device.productString] withType:MessageType_HID];
            self.lastReportedDevice = device;
        }
        [_printer printResponse:report withType:MessageType_HID];
    }
}

-(void)updateConsoleList {
    NSInteger selected = [self.consoleListBox indexOfSelectedItem] != -1 ? [self.consoleListBox indexOfSelectedItem] : 0;
    [self.consoleListBox deselectItemAtIndex:selected];
    [self.consoleListBox removeAllItems];

    for (HIDConsoleDevice * device in self.consoleListener.devices) {
        [self.consoleListBox addItemWithObjectValue:[device description]];
    }

    if ([self.consoleListBox numberOfItems] > 0) {
        [self.consoleListBox insertItemWithObjectValue:@"(All connected devices)" atIndex:0];
        [self.consoleListBox selectItemAtIndex:([self.consoleListBox numberOfItems] > selected) ? selected : 0];
    }
}

- (void)mcuSelectionChanged {
    [[NSUserDefaults standardUserDefaults] setValue:self.mcuBox.objectValueOfSelectedItem forKey:QMKMicrocontrollerKey];
}

- (void)loadMicrocontrollers {
    NSString * fileRoot = [[NSBundle mainBundle] pathForResource:@"mcu-list" ofType:@"txt"];
    NSString * fileContents = [NSString stringWithContentsOfFile:fileRoot encoding:NSUTF8StringEncoding error:nil];

    // first, separate by new line
    NSArray * allLinedStrings = [fileContents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    // choose whatever input identity you have decided. in this case ;
    for (NSString * str in allLinedStrings) {
        if ([str length] > 0) {
            [self.mcuBox addItemWithObjectValue:str];
        }
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastUsedMCU = [defaults stringForKey:QMKMicrocontrollerKey];
    if (lastUsedMCU) {
        [self.mcuBox selectItemWithObjectValue:lastUsedMCU];
    } else {
        [self.mcuBox selectItemWithObjectValue:@"atmega32u4"];
    }
}

- (void)loadKeyboards {
    NSData * data = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://api.qmk.fm/v1/keyboards"]];
    NSError * error = nil;
    if (data != nil) {
        NSArray * keyboards = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        [_keyboardBox removeAllItems];
        [_keyboardBox addItemsWithObjectValues:keyboards];
        _keyboardBox.enabled = YES;
        _keyboardBox.target = self;
        _keyboardBox.action = @selector(keyboardBoxChanged);
        [self loadKeymaps];
    }
}

- (void)keyboardBoxChanged {
    self.loadButton.enabled = self.keyboardBox.indexOfSelectedItem != -1;
}

- (void)loadKeymaps {
//    NSData * data = [NSData dataWithContentsOfURL:[NSURL URLWithString:@"http://api.qmk.fm/v1/keyboards"]];
//    NSError * error = nil;
//    NSArray * keyboards = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    [_keymapBox removeAllItems];
    [_keymapBox addItemWithObjectValue:@"default"];
    [_keymapBox selectItemAtIndex:0];
//    for (NSString * keyboard in keyboards) {
//        [_keyboardBox addItemsWithObjectValues:keyboards];
//    }
//    _keymapBox.enabled = YES;
    _loadButton.enabled = NO;
}

- (void)loadRecentDocuments {
    NSArray<NSURL *> *recentDocuments = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
    for (NSURL *document in recentDocuments) {
        [self.filepathBox addItemWithObjectValue:document.path];
    }
    if (self.filepathBox.numberOfItems > 0)
        [self.filepathBox selectItemAtIndex:0];
}

- (IBAction)loadKeymapClick:(id)sender {
    if ([_keyboardBox numberOfItems] > 0) {
        NSString * keyboard = [[_keyboardBox objectValue] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        [self setFilePath:[NSURL URLWithString:[NSString stringWithFormat:@"qmk:http://qmk.fm/compiled/%@_default.hex", keyboard]]];
    }
}

- (IBAction)clearButtonClick:(id)sender {
    [[self textView] setString: @""];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self.consoleListener stop];
}
@end
