cmake_minimum_required(VERSION 3.12)

project(OpenCV_Preprocessing)

set(OpenCV_DIR C:/opencv/build)
find_package(OpenCV REQUIRED)

add_executable(${PROJECT_NAME} src/Main.cpp)

target_link_libraries(${PROJECT_NAME} ${OpenCV_LIBS})