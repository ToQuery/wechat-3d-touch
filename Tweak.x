#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface NewMainFrameViewController : UIViewController
@property (nonatomic, strong) UITableView *tableView;
- (UIViewController *)previewingContext:(id)context viewControllerForLocation:(CGPoint)location;
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)previewingContext:(id)context commitViewController:(UIViewController *)viewControllerToCommit;
@end

@interface PeekPassThroughView : UIView
@end

@implementation PeekPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) {
        return self;
    }
    return hit;
}
@end

%hook NewMainFrameViewController

// 每个 cell 添加长按手势
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = %orig;

    if ([cell isKindOfClass:UITableViewCell.class]) {
        // 防止重复添加
        BOOL alreadyAdded = NO;
        for (UIGestureRecognizer *g in cell.gestureRecognizers) {
            if ([g isKindOfClass:UILongPressGestureRecognizer.class]) {
                alreadyAdded = YES;
                break;
            }
        }

        if (!alreadyAdded) {
            UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_my_handlePeekGesture:)];
            [cell addGestureRecognizer:longPress];
        }
    }

    return cell;
}

// 处理长按 -> 调用原生 previewingContext -> present 返回的 VC
%new
- (void)_my_handlePeekGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    UIView *cell = gesture.view;
    if (![cell isKindOfClass:UITableViewCell.class]) return;

    UITableView *tableView = nil;
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:UITableView.class]) {
            tableView = (UITableView *)subview;
            break;
        }
    }
    if (!tableView) return;

    // 取消选择cell动画
//    NSIndexPath *indexPath = [tableView indexPathForCell:(UITableViewCell *)cell];
//    if (indexPath) {
//        [tableView deselectRowAtIndexPath:indexPath animated:NO];
//    }
    
    CGPoint pointInTable = [gesture locationInView:tableView];

    // 调用微信原生的 previewingContext 接口
    UIViewController *previewVC = [self previewingContext:nil viewControllerForLocation:pointInTable];
    if (![previewVC isKindOfClass:UIViewController.class]) return;

    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    PeekPassThroughView *tapView = [[PeekPassThroughView alloc] initWithFrame:keyWindow.bounds];
    tapView.tag = 998;
    tapView.backgroundColor = UIColor.clearColor;
    tapView.userInteractionEnabled = YES;
    [keyWindow addSubview:tapView];

    // 加上背景模糊
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blur.frame = tapView.bounds;
    blur.userInteractionEnabled = NO;
    [tapView addSubview:blur];

    UIView *darkOverlay = [[UIView alloc] initWithFrame:tapView.bounds];
    darkOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.08];
    darkOverlay.userInteractionEnabled = NO;
    [tapView addSubview:darkOverlay];

    UITapGestureRecognizer *tapToDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_my_dismissPeekIfOutside:)];
    tapToDismiss.cancelsTouchesInView = NO;
    tapToDismiss.delaysTouchesBegan = NO;
    [tapView addGestureRecognizer:tapToDismiss];

    // 设置 previewVC 的样式和尺寸
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGFloat width = screenSize.width * 0.9;
    CGFloat height = screenSize.height * 0.6;
    previewVC.view.frame = CGRectMake((screenSize.width - width) / 2,
                                      (screenSize.height - height) / 2 - 40,
                                      width, height);
    if (@available(iOS 13.0, *)) {
        previewVC.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        previewVC.view.backgroundColor = [UIColor whiteColor];
    }
    previewVC.view.layer.shadowColor = [UIColor blackColor].CGColor;
    previewVC.view.layer.shadowOpacity = 0.2;
    previewVC.view.layer.shadowRadius = 10;
    previewVC.view.layer.shadowOffset = CGSizeMake(0, 4);
    previewVC.view.layer.cornerRadius = 12;
    previewVC.view.clipsToBounds = YES;

    previewVC.view.transform = CGAffineTransformMakeScale(0.8, 0.8);
    previewVC.view.alpha = 0;
    [keyWindow addSubview:previewVC.view];
    // 添加长按手势到 previewVC.view，用于触发进入对话框
    UILongPressGestureRecognizer *holdToCommit = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_my_commitPreview)];
    holdToCommit.minimumPressDuration = 0.3;
    [previewVC.view addGestureRecognizer:holdToCommit];
    previewVC.view.tag = 999;

    // 添加“进入对话框”按钮
    UIButton *enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [enterButton setTitle:@"进入对话框" forState:UIControlStateNormal];
    enterButton.titleLabel.font = [UIFont boldSystemFontOfSize:17]; // 文本大小
    enterButton.backgroundColor = [UIColor systemBackgroundColor];
//    enterButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
//    enterButton.layer.borderWidth = 1.0;
    enterButton.layer.cornerRadius = 8;
    if (@available(iOS 13.0, *)) {
        [enterButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    } else {
        [enterButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    }

    enterButton.frame = CGRectMake(previewVC.view.frame.origin.x,
                                   CGRectGetMaxY(previewVC.view.frame) + 70,
                                   previewVC.view.frame.size.width,
                                   44); // 按钮高度
    enterButton.tag = 1001;
    [enterButton addTarget:self action:@selector(_my_commitPreview) forControlEvents:UIControlEventTouchUpInside];
    [[UIApplication sharedApplication].windows.firstObject addSubview:enterButton];

    objc_setAssociatedObject(self, @selector(_my_commitPreview), enterButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 震动安排上
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }

    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        previewVC.view.transform = CGAffineTransformIdentity;
        previewVC.view.alpha = 1;
    } completion:nil];

    objc_setAssociatedObject(self, @selector(_my_dismissPeekIfOutside:), previewVC, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 点击背景 dismiss 预览
%new
- (void)_my_dismissPeekIfOutside:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:gesture.view];
    UIView *previewView = [[UIApplication sharedApplication].windows.firstObject viewWithTag:999];
    if (!previewView) return;

    if (!CGRectContainsPoint(previewView.frame, point)) {
        UIView *btn = objc_getAssociatedObject(self, @selector(_my_commitPreview));
        [btn removeFromSuperview];
        objc_setAssociatedObject(self, @selector(_my_commitPreview), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0 options:0 animations:^{
            previewView.transform = CGAffineTransformMakeScale(0.8, 0.8);
            previewView.alpha = 0;
            gesture.view.alpha = 0;
        } completion:^(BOOL finished) {
            [gesture.view removeFromSuperview];
            [previewView removeFromSuperview];
        }];
    }
}

%new
- (void)_my_commitPreview { // 进入聊天框
    
    UIView *previewView = [[UIApplication sharedApplication].windows.firstObject viewWithTag:999];
    UIView *tapView = [[UIApplication sharedApplication].windows.firstObject viewWithTag:998];
    UIView *btn = objc_getAssociatedObject(self, @selector(_my_commitPreview));
    
    if (!previewView || !tapView || !btn)
        return;

    // 轻微震动模拟 pop
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }

    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0 options:0 animations:^{
        previewView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        previewView.alpha = 0;
        tapView.alpha = 0;
        btn.alpha = 0;
    } completion:^(BOOL finished) {
        [previewView removeFromSuperview];
        [tapView removeFromSuperview];
        [btn removeFromSuperview];
        objc_setAssociatedObject(self, @selector(_my_commitPreview), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIViewController *previewVC = objc_getAssociatedObject(self, @selector(_my_dismissPeekIfOutside:));
        if (previewVC) {
            [self previewingContext:nil commitViewController:previewVC];
        }
    }];
}

%end
