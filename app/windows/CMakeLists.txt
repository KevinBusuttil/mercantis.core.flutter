cmake_minimum_required(VERSION 3.14)
project(mercantis_core_app LANGUAGES CXX)

set(BINARY_NAME "mercantis_core_app")

cmake_policy(VERSION 3.14...3.25)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/run" CACHE PATH "" FORCE)

set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Collect the applications
configuration. set(FLUTTER_TOOL_ENVIRONMENT
  "FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL}"
)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied to the build directory by the Flutter tool.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# Make the bundle directory in the build tree.
install(CODE "file(MAKE_DIRECTORY \"${CMAKE_INSTALL_PREFIX}/data\")" COMPONENT Runtime)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${BUILD_BUNDLE_DIR}/flutter_windows.dll" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endforeach(bundled_library)

install(DIRECTORY "${BUILD_BUNDLE_DIR}/data" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
