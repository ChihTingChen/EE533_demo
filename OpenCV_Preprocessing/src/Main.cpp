// Usig OpenCV 4.12.0, gcc version 15.2.0 (Rev13, Built by MSYS2 project)
// Extensions C/C++, C/C++ Compile Run, CMake, and CMake Tools
#include <opencv2/opencv.hpp>
using namespace cv;

#include <iostream>
#include <string>
using namespace std;


//OverlayImage function courtesy of stateMachine on Stack Overflow
void OverlayImage(cv::Mat& base, cv::Mat& overlay, std::pair<int, int> pos)
{
    // Create overlay mask:
    cv::Mat channels[4];
    
    // Split channels:
    cv::split(overlay, channels);

    // Threshold alpha:
    cv::Mat mask;
    cv::threshold(channels[3], mask, 0, 255, cv::THRESH_OTSU);

    // Create BGR overlay:
    cv::Mat BGR;
    std::vector<cv::Mat> temp = {channels[0], channels[1], channels[2]};
    cv::merge(temp, BGR);

    // And mask an overlay:
    cv::bitwise_and(BGR, BGR, mask);

    // Get "overlay" dimensions:
    int overlayWidth = BGR.cols;
    int overlayHeight = BGR.rows;

    // Paste "overlay" in canvas at position pos:
    // Hint: small_image.copyTo(big_image(cv::Rect(x,y,small_image.cols, small_image.rows)));
    BGR.copyTo(base(cv::Rect(pos.first, pos.second, overlayWidth, overlayHeight)));
}

int main(int argc, const char** argv)
{
    /*********************************************/
    /*********************************************/
    /*********************************************/
    /*********************************************/
    // CHANGE THIS PATH TO THE IMAGE PATH ON YOUR MACHINE
    string image_path = "C:/Users/njroc/OneDrive/Documents/School/USC_Spring_2026/EE533/OpenCV_Preprocessing/src/bobder.jpg";  
    string grey_path = "C:/Users/njroc/OneDrive/Documents/School/USC_Spring_2026/EE533/OpenCV_Preprocessing/src/grey.jpg";  
    /*********************************************/
    /*********************************************/
    /*********************************************/
    /*********************************************/

    Mat img = imread(image_path, IMREAD_COLOR);
    Mat grey = imread(grey_path, IMREAD_COLOR);

    Mat img_rgb;

    cvtColor(img, img_rgb, 4); //the parameter '4' is the conversion code of the image the conversion code specifies what type
    // of image data we are taking in and putting out, they all can be seen in the documnetion for cvtColor
    int h_half = img_rgb.rows / 2;
    int w_half = img_rgb.cols / 2;

    if(img.empty())
    {
        std::cout << "Could not read the image: " << image_path << std::endl;
        return 1;
    }
 
    Mat img_grey;
    cvtColor(img, img_grey, 6, 0);
    int h_grey = img_grey.rows / 2;
    int w_grey = img_grey.cols / 2;


    Mat Quad1 = img_rgb(Range(0, h_half - 1), Range(0, w_half - 1));
    Mat GQuad1 = img_grey(Range(0, h_half - 1), Range(0, w_half - 1));
    Mat Quad2 = img_rgb(Range(0, h_half - 1), Range(w_half, img_rgb.cols - 1));
    Mat GQuad2 = img_grey(Range(0, h_half - 1), Range(w_half, img_rgb.cols - 1));
    Mat Quad3 = img_rgb(Range(h_half, img_rgb.rows - 1), Range(0, w_half - 1));
    Mat GQuad3 = img_grey(Range(h_half, img_rgb.rows - 1), Range(0, w_half - 1));
    Mat Quad4 = img_rgb(Range(h_half, img_rgb.rows - 1), Range(w_half, img_rgb.cols - 1)); 
    Mat GQuad4 = img_grey(Range(h_half, img_rgb.rows - 1), Range(w_half, img_rgb.cols - 1)); 

    int mid_x = (grey.cols - Quad1.cols)/2;
    int mid_y = (grey.rows - Quad1.rows)/2;
    OverlayImage(grey, Quad1, std::pair<int, int>(mid_x, mid_y));
    OverlayImage(grey, Quad2, std::pair<int, int>(mid_x, mid_y));
    OverlayImage(grey, Quad3, std::pair<int, int>(mid_x, mid_y));
    OverlayImage(grey, Quad4, std::pair<int, int>(mid_x, mid_y));
    Mat finalImage1;
    Mat finalImage2;
    Mat finalImage3;
    Mat finalImage4;
    normalize(GQuad1, finalImage1, 0, 255, NORM_MINMAX);
    normalize(GQuad2, finalImage2, 0, 255, NORM_MINMAX);
    normalize(GQuad3, finalImage3, 0, 255, NORM_MINMAX);
    normalize(GQuad4, finalImage4, 0, 255, NORM_MINMAX);
    std::cout << finalImage1.type() << std::endl;
    cout << finalImage1 << endl;

    cout << "Each quadrant is "<< finalImage1.cols << " pixels wide and " << finalImage1.rows << " pixels tall!" << endl;

    imshow("Display window", img); //original image
    imshow("Quad1", Quad1); // rgb image
    imshow("Grey Quad", GQuad1); 
    imshow("finalImage1", finalImage1); 
    imshow("finalImage2", finalImage2); 
    imshow("finalImage3", finalImage3); 
    imshow("finalImage4", finalImage4); 
    int k = waitKey(0); // Wait for a keystroke in the window

    if(k == 's')
    {
        imwrite("bobder.png", img);
    }
    return 0;
}