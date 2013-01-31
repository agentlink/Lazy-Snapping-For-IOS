//
//  AutoCutoutViewController.h
//  AutoCutout
//
//  Created by agent on 12-11-13.
//  Copyright (c) 2012年 agent. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MBProgressHUD.h"

@interface AutoCutoutViewController: UIViewController<UIImagePickerControllerDelegate, UINavigationControllerDelegate, MBProgressHUDDelegate>
{
    MBProgressHUD *HUD;
}
@property (strong,nonatomic) UIImagePickerController *imgPickerControll;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

- (IBAction)selectImg:(id)sender;
- (IBAction)findContours:(id)sender;
- (IBAction)preSwitch:(id)sender;
- (IBAction)backSwitch:(id)sender;

@end
