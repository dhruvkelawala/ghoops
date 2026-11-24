//go:build darwin && cgo

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
unsigned char *gh_qr(const char *text, int *size) {
 @autoreleasepool {
  NSData *data=[[NSString stringWithUTF8String:text] dataUsingEncoding:NSUTF8StringEncoding];
  CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];
  [filter setValue:data forKey:@"inputMessage"];
  [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
  CIImage *image=filter.outputImage;
  if (!image) return NULL;
  int n=(int)image.extent.size.width;
  unsigned char *pixels=malloc(n*n);
  if (!pixels) return NULL;
  CGColorSpaceRef gray=CGColorSpaceCreateDeviceGray();
  [[CIContext contextWithOptions:nil] render:image toBitmap:pixels rowBytes:n bounds:image.extent format:kCIFormatL8 colorSpace:gray];
  CGColorSpaceRelease(gray);
  *size=n;
  return pixels;
 }
}
