#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "Stex::Stex" for configuration "Release"
set_property(TARGET Stex::Stex APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(Stex::Stex PROPERTIES
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/bin/Stex.exe"
  )

list(APPEND _cmake_import_check_targets Stex::Stex )
list(APPEND _cmake_import_check_files_for_Stex::Stex "${_IMPORT_PREFIX}/bin/Stex.exe" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
