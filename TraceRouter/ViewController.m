//
//  ViewController.m
//  TraceRouter
//
//  Created by Naver on 2015. 12. 4..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "ViewController.h"
#import "LVTraceRouteManager.h"
@interface ViewController ()

@property (strong, nonatomic) UITextField *txfHostName;
@property (strong, nonatomic) UIButton *doButton;
@property (strong, nonatomic) UITextView *resultView;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;

@property (strong, nonatomic) LVTraceRouteManager *traceRouteManager;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.6 alpha:0.8];
    
    self.txfHostName = [[UITextField alloc] initWithFrame:CGRectMake(5, 25, 200, 30)];
    self.txfHostName.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    self.txfHostName.font = [UIFont systemFontOfSize:13];
    self.txfHostName.text = @"www.naver.com";
    [self.view addSubview:self.txfHostName];
    
    self.doButton = [[UIButton alloc] initWithFrame:CGRectMake(208, 25, 50, 30)];
    [self.doButton setTitle:@"DoIT!" forState:UIControlStateNormal];
    [self.doButton addTarget:self action:@selector(doTraceRouteHost) forControlEvents:UIControlEventTouchUpInside];
    self.doButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.8 blue:0.8 alpha:0.8];
    self.doButton.titleLabel.font = [UIFont systemFontOfSize:11];
    [self.view addSubview:self.doButton];
    
    CGSize fSize = self.view.frame.size;
    self.resultView = [[UITextView alloc] initWithFrame:CGRectMake(5, 58, fSize.width-10, fSize.height-43)];
    self.resultView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    self.resultView.editable = NO;
    [self.resultView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.view addSubview:self.resultView];
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake((fSize.width/2)-10, (fSize.height/2)-10, 20, 20)];
    self.spinner.color = [UIColor blackColor];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    
    self.traceRouteManager = [[LVTraceRouteManager alloc] init];
    __block typeof(self) wself = self;
    self.traceRouteManager.success = ^(NSString *resultString) {
        dispatch_async(dispatch_get_main_queue(), ^{
            wself.resultView.text = resultString;
            [wself.spinner stopAnimating];
            wself.doButton.enabled = YES;
        });
    };
    self.traceRouteManager.fail = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            wself.resultView.text = [error description];
            [wself.spinner stopAnimating];
            wself.doButton.enabled = YES;
        });
    };
    
    self.traceRouteManager.maxTTL = 20;
}

- (void)doTraceRouteHost{
    [self.traceRouteManager addHost:self.txfHostName.text];
    [self.spinner startAnimating];
    self.doButton.enabled = NO;
}

- (void)tracerouteResult:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.resultView.text = dict[@"Result"];
        [self.spinner stopAnimating];
    });
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self.txfHostName endEditing:YES];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
