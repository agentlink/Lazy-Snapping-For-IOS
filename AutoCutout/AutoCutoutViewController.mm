//
//  AutoCutoutViewController.m
//  AutoCutout
//
//  Created by agent on 12-11-13.
//  Copyright (c) 2012年 agent. All rights reserved.
//

#import "AutoCutoutViewController.h"
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/objdetect/objdetect.hpp>
#import <opencv2/legacy/legacy.hpp>

#import <opencv2/highgui/highgui.hpp>
#include <opencv2/opencv.hpp>
#include "maxflow-v3.01/graph.h"
#include <vector>
#include <iostream>
#include <cmath>
using namespace std;

typedef Graph<float,float,float> GraphType;
class LasySnapping{
    
    public :
    LasySnapping():graph(NULL){
        avgForeColor[0] = 0;
        avgForeColor[1] = 0;
        avgForeColor[2] = 0;
        
        avgBackColor[0] = 0;
        avgBackColor[1] = 0;
        avgBackColor[2] = 0;
    }
    ~LasySnapping(){
        if(graph){
            delete graph;
        }
    };
    private :
    vector<CvPoint> forePts;
    vector<CvPoint> backPts;
    IplImage* image;
    // average color of foreground points
    unsigned char avgForeColor[3];
    // average color of background points
    unsigned char avgBackColor[3];
    public :
    void setImage(IplImage* image){
        this->image = image;
        graph = new GraphType(image->width*image->height,image->width*image->height*2);
    }
    // include-pen locus
    void setForegroundPoints(vector<CvPoint> pts){
        forePts.clear();
        for(int i =0; i< pts.size(); i++){
            if(!isPtInVector(pts[i],forePts)){
                forePts.push_back(pts[i]);
            }
        }
        if(forePts.size() == 0){
            return;
        }
        int sum[3] = {0};
        for(int i =0; i < forePts.size(); i++){
            unsigned char* p = (unsigned char*)image->imageData + forePts[i].x * 3
            + forePts[i].y*image->widthStep;
            sum[0] += p[0];
            sum[1] += p[1];
            sum[2] += p[2];
        }
        cout<<sum[0]<<" " <<forePts.size()<<endl;
        avgForeColor[0] = sum[0]/forePts.size();
        avgForeColor[1] = sum[1]/forePts.size();
        avgForeColor[2] = sum[2]/forePts.size();
    }
    // exclude-pen locus
    void setBackgroundPoints(vector<CvPoint> pts){
        backPts.clear();
        for(int i =0; i< pts.size(); i++){
            if(!isPtInVector(pts[i],backPts)){
                backPts.push_back(pts[i]);
            }
        }
        if(backPts.size() == 0){
            return;
        }
        int sum[3] = {0};
        for(int i =0; i < backPts.size(); i++){
            unsigned char* p = (unsigned char*)image->imageData + backPts[i].x * 3 +
            backPts[i].y*image->widthStep;
            sum[0] += p[0];
            sum[1] += p[1];
            sum[2] += p[2];
        }
        avgBackColor[0] = sum[0]/backPts.size();
        avgBackColor[1] = sum[1]/backPts.size();
        avgBackColor[2] = sum[2]/backPts.size();
    }
    // return maxflow of graph
    int runMaxflow();
    // get result, a grayscale mast image indicating forground by 255 and background by 0
    IplImage* getImageMask();
    private :
    float colorDistance(unsigned char* color1, unsigned char* color2);
    float minDistance(unsigned char* color, vector<CvPoint> points);
    bool isPtInVector(CvPoint pt, vector<CvPoint> points);
    void getE1(unsigned char* color,float* energy);
    float getE2(unsigned char* color1,unsigned char* color2);
    
    GraphType *graph;
};

float LasySnapping::colorDistance(unsigned char* color1, unsigned char* color2)
{
    return sqrt((color1[0]-color2[0])*(color1[0]-color2[0])+
                (color1[1]-color2[1])*(color1[1]-color2[1])+
                (color1[2]-color2[2])*(color1[2]-color2[2]));
}

float LasySnapping::minDistance(unsigned char* color, vector<CvPoint> points)
{
    float distance = -1;
    for(int i =0 ; i < points.size(); i++){
        unsigned char* p = (unsigned char*)image->imageData + points[i].y * image->widthStep +
        points[i].x * image->nChannels;
        float d = colorDistance(p,color);
        if(distance < 0 ){
            distance = d;
        }else{
            if(distance > d){
                distance = d;
            }
        }
    }
    return 0.0;
}
bool LasySnapping::isPtInVector(CvPoint pt, vector<CvPoint> points)
{
    for(int i =0 ; i < points.size(); i++){
        if(pt.x == points[i].x && pt.y == points[i].y){
            return true;
        }
    }
    return false;
}
void LasySnapping::getE1(unsigned char* color,float* energy)
{
    // average distance
    float df = colorDistance(color,avgForeColor);
    float db = colorDistance(color,avgBackColor);
    // min distance from background points and forground points
    // float df = minDistance(color,forePts);
    // float db = minDistance(color,backPts);
    energy[0] = df/(db+df);
    energy[1] = db/(db+df);
}
float LasySnapping::getE2(unsigned char* color1,unsigned char* color2)
{
    const float EPSILON = 0.01;
    float lambda = 100;
    return lambda/(EPSILON+
                   (color1[0]-color2[0])*(color1[0]-color2[0])+
                   (color1[1]-color2[1])*(color1[1]-color2[1])+
                   (color1[2]-color2[2])*(color1[2]-color2[2]));
}

int LasySnapping::runMaxflow()
{
    const float INFINNITE_MAX = 1e10;
    int indexPt = 0;
    for(int h = 0; h < image->height; h ++){
        unsigned char* p = (unsigned char*)image->imageData + h *image->widthStep;
        for(int w = 0; w < image->width; w ++){
            // calculate energe E1
            float e1[2]={0};
            if(isPtInVector(cvPoint(w,h),forePts)){
                e1[0] =0;
                e1[1] = INFINNITE_MAX;
            }else if(isPtInVector(cvPoint(w,h),backPts)){
                e1[0] = INFINNITE_MAX;
                e1[1] = 0;
            }else {
                getE1(p,e1);
            }
            // add node
            graph->add_node();
            graph->add_tweights(indexPt, e1[0],e1[1]);
            // add edge, 4-connect
            if(h > 0 && w > 0){
                float e2 = getE2(p,p-3);
                graph->add_edge(indexPt,indexPt-1,e2,e2);
                e2 = getE2(p,p-image->widthStep);
                graph->add_edge(indexPt,indexPt-image->width,e2,e2);
            }
            
            p+= 3;
            indexPt ++;
        }
    }
    
    return graph->maxflow();
}
IplImage* LasySnapping::getImageMask()
{
    IplImage* gray = cvCreateImage(cvGetSize(image),8,1);
    int indexPt =0;
    for(int h =0; h < image->height; h++){
        unsigned char* p = (unsigned char*)gray->imageData + h*gray->widthStep;
        for(int w =0 ;w <image->width; w++){
            if (graph->what_segment(indexPt) == GraphType::SOURCE){
                *p = 0;
            }else{
                *p = 255;
            }
            p++;
            indexPt ++;
        }
    }
    return gray;
}

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};
@interface UIImage(UIImageScale)
-(UIImage*)scaleToSize:(CGSize)size;
-(UIImage*)getSubImage:(CGRect)rect;
@end

@implementation UIImage(UIImageScale)

//截取部分图像
-(UIImage*)getSubImage:(CGRect)rect
{
    CGImageRef subImageRef = CGImageCreateWithImageInRect(self.CGImage, rect);
    CGRect smallBounds = CGRectMake(0, 0, CGImageGetWidth(subImageRef), CGImageGetHeight(subImageRef));
    
    UIGraphicsBeginImageContext(smallBounds.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextDrawImage(context, smallBounds, subImageRef);
    UIImage* smallImage = [UIImage imageWithCGImage:subImageRef];
    UIGraphicsEndImageContext();
    CGImageRelease(subImageRef);
    
    return smallImage;
}

-(UIImage *)scaleToSize:(CGSize)targetSize
{
    UIImage *sourceImage = self;
    UIImage *newImage = nil;
    
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    
    CGFloat targetWidth = targetSize.width;
    CGFloat targetHeight = targetSize.height;
    
    CGFloat scaleFactor = 0.0;
    CGFloat scaledWidth = targetWidth;
    CGFloat scaledHeight = targetHeight;
    
    CGPoint thumbnailPoint = CGPointMake(0.0,0.0);
    
    if (CGSizeEqualToSize(imageSize, targetSize) == NO) {
        
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;
        
        if (widthFactor < heightFactor)
            scaleFactor = widthFactor;
        else
            scaleFactor = heightFactor;
        
        scaledWidth  = width * scaleFactor;
        scaledHeight = height * scaleFactor;
        
        // center the image
        
        if (widthFactor < heightFactor) {
            thumbnailPoint.y = (targetHeight - scaledHeight) * 0.5;
        } else if (widthFactor > heightFactor) {
            thumbnailPoint.x = (targetWidth - scaledWidth) * 0.5;
        }
    }
    
    
    // this is actually the interesting part:
    
    UIGraphicsBeginImageContext(targetSize);
    
    CGRect thumbnailRect = CGRectZero;
    thumbnailRect.origin = thumbnailPoint;
    thumbnailRect.size.width  = scaledWidth;
    thumbnailRect.size.height = scaledHeight;
    
    [sourceImage drawInRect:thumbnailRect];
    
    newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if(newImage == nil) NSLog(@"could not scale image");
    
    return newImage ;
}

- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees
{
    // calculate the size of the rotated view's containing box for our drawing space
    UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.size.width, self.size.height)];
    CGAffineTransform t = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
    rotatedViewBox.transform = t;
    CGSize rotatedSize = rotatedViewBox.frame.size;
    
    // Create the bitmap context
    UIGraphicsBeginImageContext(rotatedSize);
    CGContextRef bitmap = UIGraphicsGetCurrentContext();
    
    // Move the origin to the middle of the image so we will rotate and scale around the center.
    CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2);
    
    //   // Rotate the image context
    CGContextRotateCTM(bitmap, DegreesToRadians(degrees));
    
    // Now, draw the rotated/scaled image into the context
    CGContextScaleCTM(bitmap, 1.0, -1.0);
    CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), [self CGImage]);
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}

@end

@interface AutoCutoutViewController ()
{
    // global
    vector<CvPoint> forePts;
    vector<CvPoint> backPts;
    int currentMode;// indicate foreground or background, foreground as default
    CvScalar paintColor[2];
    
    IplImage* lazyImage;
    IplImage* lazyImageDraw;
    int SCALE;
    
    IplImage* marker_mask;
    IplImage* markers;
    IplImage* img0, *img, *img_gray, *wshed;
    CvPoint prev_pt;
}
@end

@implementation AutoCutoutViewController


- (cv::Mat)cvMatFromUIImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to  data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    //CGColorSpaceRelease(colorSpace);
    
    return cvMat;
}

-(UIImage *)UIImageFromCVMat:(cv::Mat)cvMat
{
    NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.elemSize()*cvMat.total()];
    CGColorSpaceRef colorSpace;
    
    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(( CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    CGImageRef imageRef = CGImageCreate(cvMat.cols,                                 //width
                                        cvMat.rows,                                 //height
                                        8,                                          //bits per component
                                        8 * cvMat.elemSize(),                       //bits per pixel
                                        cvMat.step[0],                            //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );
    
    
    // Getting UIImage from CGImage
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}

- (cv::Mat)cvMatGrayFromUIImage:(UIImage *)image
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat cvMat(rows, cols, CV_8UC1); // 8 bits per component, 1 channels
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    8,                          // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    //CGColorSpaceRelease(colorSpace);
    
    return cvMat;
}

// NOTE 戻り値は利用後cvReleaseImage()で解放してください
- (IplImage*) createIplImageFromUIImage:(UIImage*)image
{
    // CGImageをUIImageから取得
    CGImageRef imageRef = image.CGImage;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // 一時的なIplImageを作成
    IplImage *iplimage = cvCreateImage(cvSize(image.size.width, image.size.height),
                                       IPL_DEPTH_8U,
                                       4);
    // CGContextを一時的なIplImageから作成
    CGContextRef contextRef = CGBitmapContextCreate(iplimage->imageData,
                                                    iplimage->width,
                                                    iplimage->height,
                                                    iplimage->depth,
                                                    iplimage->widthStep,
                                                    colorSpace,
                                                    kCGImageAlphaPremultipliedLast|kCGBitmapByteOrderDefault);
    // CGImageをCGContextに描画
    CGContextDrawImage(contextRef,
                       CGRectMake(0, 0, image.size.width, image.size.height),
                       imageRef);
    CGContextRelease(contextRef);
    CGColorSpaceRelease(colorSpace);
    
    // 最終的なIplImageを作成
    IplImage *ret = cvCreateImage(cvGetSize(iplimage), IPL_DEPTH_8U, 3);
    //	cvCvtColor(iplimage, ret, CV_RGBA2BGR);
    cvCvtColor(iplimage, ret, CV_RGBA2RGB);
    cvReleaseImage(&iplimage);
    
    return ret;
}

// NOTE IplImageは事前にRGBモードにしておいてください。
- (UIImage*) createUIImageFromIplImage:(IplImage*)image
{
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // CGImageのためのバッファを確保
    NSData *data = [NSData dataWithBytes:image->imageData length:image->imageSize];
    CGDataProviderRef provider =
    CGDataProviderCreateWithCFData((CFDataRef)data);
    // IplImageのデータからCGImageを作成
    CGImageRef imageRef = CGImageCreate(image->width,
                                        image->height,
                                        image->depth,
                                        image->depth * image->nChannels,
                                        image->widthStep,
                                        colorSpace,
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    // UIImageをCGImageから取得
    UIImage *ret = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return ret;
}

-(CGRect)frameForImage:(UIImage*)image inImageViewAspectFit:(UIImageView*)imageView
{
    float imageRatio = image.size.width / image.size.height;
    
    float viewRatio = imageView.frame.size.width / imageView.frame.size.height;
    
    if(imageRatio < viewRatio)
    {
        float scale = imageView.frame.size.height / image.size.height;
        
        float width = scale * image.size.width;
        
        float topLeftX = (imageView.frame.size.width - width) * 0.5;
        
        return CGRectMake(topLeftX, 0, width, imageView.frame.size.height);
    }
    else
    {
        float scale = imageView.frame.size.width / image.size.width;
        
        float height = scale * image.size.height;
        
        float topLeftY = (imageView.frame.size.height - height) * 0.5;
        
        return CGRectMake(0, topLeftY, imageView.frame.size.width, height);
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (_imgPickerControll == nil)
    {
        _imgPickerControll = [[UIImagePickerController alloc] init];
        _imgPickerControll.delegate = self;
    }
    
    currentMode = 0;// indicate foreground or background, foreground as default
    paintColor[0] = CV_RGB(0,0,255);
    paintColor[1] = CV_RGB(255,0,0);
    
    lazyImage = NULL;
    lazyImageDraw = NULL;
    
    marker_mask = 0;
    markers = 0;
    img0 = 0;
    img = 0;
    img_gray = 0;
    wshed = 0;
    prev_pt = {-1,-1};
    
    SCALE = 1;
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingImage:(UIImage *)image editingInfo:(NSDictionary *)editingInfo
{
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    UIGraphicsBeginImageContext(rect.size);
    [image drawInRect:rect];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    _imageView.image = [image scaleToSize:[self frameForImage:image inImageViewAspectFit:_imageView].size];
    lazyImage = [self createIplImageFromUIImage:_imageView.image ];
    lazyImageDraw = [self createIplImageFromUIImage:_imageView.image ];
    
    img0 = [self createIplImageFromUIImage:_imageView.image ];
    
    img = cvCloneImage(img0);
    // 用于显示的原图像
    img_gray = cvCloneImage(img0);
    // 用于和分割出的颜色块进行混合
    wshed = cvCreateImage(cvGetSize(img), 8, 3);
    // 用于存储分割出的颜色块和最后的效果图
    marker_mask = cvCreateImage(cvGetSize(img), 8, 1);
    // 用于记录用户标记区域的画布,并在此基础上制作用于分水岭算法使用的markers
    markers = cvCreateImage(cvGetSize(img), IPL_DEPTH_32S, 1);
    cvCvtColor(img, marker_mask, CV_BGR2GRAY);
    cvCvtColor(marker_mask, img_gray, CV_GRAY2BGR);
    
    cvZero(marker_mask);
    cvZero( wshed );
    
    forePts.clear();
    backPts.clear();
    currentMode = 0;
    
    [picker dismissModalViewControllerAnimated:NO];
    picker = nil;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    // tell our delegate we are finished with the picker
    //[picker dismissModalViewControllerAnimated:NO];
    [[picker presentingViewController] dismissViewControllerAnimated:NO completion:nil];
    picker = nil;
}

- (IBAction)selectImg:(id)sender {
    [self presentViewController:_imgPickerControll animated:NO completion:nil];
}

//lazy snapping算法
- (void)lazySnapping{
    if(backPts.size() == 0 && forePts.size() == 0){
        return;
    }
    
    if (_imageView.image != nil) {
        IplImage* imageLS = cvCreateImage(cvSize(lazyImage->width/SCALE,lazyImage->height/SCALE),8,3);
        
        LasySnapping ls;
        cvResize(lazyImage,imageLS);
        ls.setImage(imageLS);
        ls.setBackgroundPoints(backPts);
        ls.setForegroundPoints(forePts);
        ls.runMaxflow();
        IplImage* mask = ls.getImageMask();
        IplImage* gray = cvCreateImage(cvGetSize(lazyImage),8,1);
        cvResize(mask,gray);
        // edge
        cvCanny(gray,gray,50,150,3);
        
        IplImage* showImg = cvCloneImage(lazyImageDraw);
        for(int h =0; h < lazyImage->height; h ++){
            unsigned char* pgray = (unsigned char*)gray->imageData + gray->widthStep*h;
            unsigned char* pimage = (unsigned char*)showImg->imageData + showImg->widthStep*h;
            for(int width  =0; width < lazyImage->width; width++){
                if(*pgray++ != 0 ){
                    pimage[0] = 0;
                    pimage[1] = 255;
                    pimage[2] = 0;
                }
                pimage+=3;
            }
        }
        
        _imageView.image = [self createUIImageFromIplImage:showImg];
        
        cvReleaseImage(&imageLS);
        cvReleaseImage(&mask);
        cvReleaseImage(&showImg);
        cvReleaseImage(&gray);
        
    }
}

//watershed算法
- (void)waterShed{
    CvRNG rng = cvRNG(-1);
    // 定义一个随机化生成器并初始化为-1,配合下面cvRandInt(&rng)生成随机数,现在知道为什么会变颜色了吧
    
    CvMemStorage* storage = cvCreateMemStorage(0);
    CvSeq* contours = 0;
    
    int comp_count = 1;
    // 粗看以为这是记录轮廓数目呢,其实不然,他将把每个轮廓设为同一像素值
    cvFindContours( marker_mask, storage, &contours, sizeof(CvContour),CV_RETR_CCOMP, CV_CHAIN_APPROX_SIMPLE );
    cvZero( markers );
    for( ; contours != 0; contours = contours->h_next, comp_count++)
    {
        cvDrawContours( markers, contours, cvScalarAll(comp_count+1),cvScalarAll(comp_count+1), -1, -1, 8, cvPoint(0,0) );
    }
    // 上面这些最后得到markers 将会是一些数值块，每个轮廓区域内都有同一像素值
    // 到此时Watershed 终于得到了它如饥似渴的 markers 这个markers 中记录了刚刚
    // 用户用鼠标勾勒的感兴趣区域
    
    CvMat* color_tab;
    color_tab = cvCreateMat(1, comp_count, CV_8UC3);
    // 构造一个一维8bit无符号3通道元素类型的矩阵,用来记录一些随机的颜色
    for(int i = 0; i < comp_count; i++)
    {
        uchar* ptr = color_tab->data.ptr + i*3;
        ptr[0] = (uchar)(cvRandInt(&rng)%180 + 50);
        ptr[1] = (uchar)(cvRandInt(&rng)%180 + 50);
        ptr[2] = (uchar)(cvRandInt(&rng)%180 + 50);
    }
    
    {// 千呼万唤始出来的cvWatershed
        cvWatershed(img0, markers);
        // 上面的t用来计算此算法运行时间
        
        /************************************************************************/
        /* markers中包含了一些用户感兴趣的区域,每个区域用1、2、3。。一些像素值标注,经过
         此算法后,markers会变成什么样呢？要知道markers中标注的只是用户用鼠标轻描淡写的
         一些区域，把这些区域想像成一些湖泊，如果只有一个区域，则代表整幅图将会被这一个
         湖泊淹没，上面color_tab 正是用来记录每个湖泊的颜色。如果用户标注了两个区域，则
         湖泊会沿着这两个区域蔓延，直到把图片分成两个湖泊，这两个湖泊不是无规律的，而是
         尽可能把图像的轮廓分隔开。如标注多个区域，则将形成多种颜色的湖泊，此算法会把把
         每个湖泊的分水岭赋为 -1，即用来分隔这些湖泊，下面图片展示了这些湖泊把整幅图都分
         隔开了 */
        /************************************************************************/
    }
    
    // paint the watershed image
    for(int i = 0; i < markers->height; i++)
        for(int j = 0; j < markers->width; j++)
        {
            int idx = CV_IMAGE_ELEM( markers, int, i, j );
            // idx得到了markers 在(i, j)坐标的的像素值,这个值对应color_tab中的一种颜色
            // 因为markers 中的像素值就是用1-comp_count 的像素值标注的
            uchar* dst = &CV_IMAGE_ELEM( wshed, uchar, i, j*3 );
            // dst得到了wshed图像 (i, j)像素数据的首地址,因为乘3是因为3通道
            
            if( idx == -1 )
                // 在wshed图像中将markers 中得到的分水岭标记为白色,原先-1将显示黑色
                dst[0] = dst[1] = dst[2] = (uchar)255;
            else if( idx <= 0 || idx > comp_count )
                dst[0] = dst[1] = dst[2] = (uchar)0; // should not get here
            else
            {
                uchar* ptr = color_tab->data.ptr + (idx-1)*3;
                // 指向idx 所对应的颜色通道，这些颜色是上面随机生成的
                dst[0] = ptr[0]; dst[1] = ptr[1]; dst[2] = ptr[2];
                // 把对应的像素值赋给wshed 图像
            }
        }
    
    cvAddWeighted( wshed, 0.5, img_gray, 0.5, 0, wshed );
    // 可以注释掉看下效果
    _imageView.image = [self createUIImageFromIplImage:wshed];
    cvReleaseMemStorage( &storage );
    cvReleaseMat( &color_tab );
}

- (IBAction)findContours:(id)sender {
    /**HUD = [[MBProgressHUD alloc] initWithView:self.navigationController.view];
     [self.navigationController.view addSubview:HUD];
     
     HUD.dimBackground = YES;
     
     // Regiser for HUD callbacks so we can remove it from the window at the right time
     HUD.delegate = self;
     
     // Show the HUD while the provided method executes in a new thread
     [HUD showWhileExecuting:@selector(delBackground) onTarget:self withObject:nil animated:YES];**/
    [self lazySnapping];
}

- (IBAction)preSwitch:(id)sender {
    currentMode = 0;
}

- (IBAction)backSwitch:(id)sender {
    currentMode = 1;
}

- (void)drawLineLazySnapping:(CGPoint)locationPoint{
    if (_imageView.image != nil) {
        
        CGRect imageFrame = [self frameForImage:_imageView.image inImageViewAspectFit:_imageView];
        
        CvPoint pt = cv::Point2f(locationPoint.x - imageFrame.origin.x,locationPoint.y - imageFrame.origin.y);
        if( prev_pt.x < 0 )
            prev_pt = pt;
        
        if(currentMode == 0){//foreground
            forePts.push_back(cv::Point2f(pt.x/SCALE,pt.y/SCALE));
        }else{//background
            backPts.push_back(cv::Point2f(pt.x/SCALE,pt.y/SCALE));
        }
        
        cvLine(lazyImageDraw,prev_pt,pt,paintColor[currentMode],5,8,0);
        
        _imageView.image = [self createUIImageFromIplImage:lazyImageDraw];
    }
    
}

- (void)drawLineWatershed:(CGPoint)locationPoint{
    if (_imageView.image != nil) {
        CGRect imageFrame = [self frameForImage:_imageView.image inImageViewAspectFit:_imageView];
        
        CvPoint pt = cv::Point2f(locationPoint.x - imageFrame.origin.x,locationPoint.y - imageFrame.origin.y);
        if( prev_pt.x < 0 )
            prev_pt = pt;
        cvLine(marker_mask, prev_pt, pt, cvScalarAll(255), 5, 8, 0);
        // 实际标记 marker_mask 才会被算法用到
        cvLine(img, prev_pt, pt, cvScalarAll(255), 5, 8, 0);
        // img标记只便于用户观察
        prev_pt = pt;
        _imageView.image = [self createUIImageFromIplImage:img];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint locationPoint = [[touches anyObject] locationInView:self.imageView];
    CGRect imageFrame = [self frameForImage:_imageView.image inImageViewAspectFit:_imageView];
    prev_pt = cv::Point2f(locationPoint.x - imageFrame.origin.x,locationPoint.y - imageFrame.origin.y);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint locationPoint = [[touches anyObject] locationInView:self.imageView];
    [self drawLineLazySnapping:locationPoint];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    prev_pt = cv::Point2f(-1,-1);
}

@end
