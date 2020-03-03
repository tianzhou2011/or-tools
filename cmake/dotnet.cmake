if(NOT BUILD_DOTNET)
  return()
endif()

if(NOT TARGET ortools::ortools)
  message(FATAL_ERROR ".Net: missing ortools TARGET")
endif()

find_package(SWIG)
include(UseSWIG)

#if(${SWIG_VERSION} VERSION_GREATER_EQUAL 4)
#  list(APPEND CMAKE_SWIG_FLAGS "-doxygen")
#endif()

if(UNIX AND NOT APPLE)
  list(APPEND CMAKE_SWIG_FLAGS "-DSWIGWORDSIZE64")
endif()

# Setup Dotnet
find_program (DOTNET_CLI NAMES dotnet)
if(NOT DOTNET_EXECUTABLE)
  message(FATAL_ERROR "Check for dotnet Program: not found")
else()
  message(STATUS "Found dotnet Program: ${DOTNET_EXECUTABLE}")
endif()

# Generate Protobuf .Net sources
set(PROTO_DOTNETS)
file(GLOB_RECURSE proto_dotnet_files RELATIVE ${PROJECT_SOURCE_DIR}
  "ortools/constraint_solver/*.proto"
  "ortools/linear_solver/*.proto"
  "ortools/sat/*.proto"
  "ortools/util/*.proto"
  )
list(REMOVE_ITEM proto_dotnet_files "ortools/constraint_solver/demon_profiler.proto")
foreach(PROTO_FILE IN LISTS proto_dotnet_files)
  #message(STATUS "protoc proto(dotnet): ${PROTO_FILE}")
  get_filename_component(PROTO_DIR ${PROTO_FILE} DIRECTORY)
  get_filename_component(PROTO_NAME ${PROTO_FILE} NAME_WE)
  set(PROTO_DOTNET ${PROJECT_BINARY_DIR}/dotnet/${PROTO_DIR}/${PROTO_NAME}.pb.cs)
  #message(STATUS "protoc dotnet: ${PROTO_DOTNET}")
  add_custom_command(
    OUTPUT ${PROTO_DOTNET}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${PROJECT_BINARY_DIR}/dotnet/${PROTO_DIR}
    COMMAND protobuf::protoc
    "--proto_path=${PROJECT_SOURCE_DIR}"
    "--csharp_out=${PROJECT_BINARY_DIR}/dotnet/${PROTO_DIR}"
    "--csharp_opt=file_extension=.pb.cs"
    ${PROTO_FILE}
    DEPENDS ${PROTO_FILE} protobuf::protoc
    COMMENT "Running C++ protocol buffer compiler on ${PROTO_FILE}"
    VERBATIM)
  list(APPEND PROTO_DOTNETS ${PROTO_DOTNET})
endforeach()
add_custom_target(Dotnet${PROJECT_NAME}_proto DEPENDS ${PROTO_DOTNETS} ortools::ortools)

# Create the native library
add_library(google-ortools-native SHARED "")
set_target_properties(google-ortools-native PROPERTIES
  PREFIX "")

# Swig wrap all libraries
set(OR_TOOLS_DOTNET Google.OrTools)
foreach(SUBPROJECT IN ITEMS algorithms graph linear_solver constraint_solver sat util)
  add_subdirectory(ortools/${SUBPROJECT}/csharp)
  target_link_libraries(google-ortools-native PRIVATE dotnet_${SUBPROJECT})
endforeach()

############################
##  .Net Runtime Package  ##
############################
file(COPY tools/doc/orLogo.png DESTINATION dotnet)
set(DOTNET_PACKAGES_DIR "../packages")
configure_file(ortools/dotnet/Directory.Build.props.in dotnet/Directory.Build.props)

# Build or retrieve .snk file
if(DEFINED ENV{DOTNET_SNK})
  add_custom_command(OUTPUT dotnet/or-tools.snk
    COMMAND ${CMAKE_COMMAND} -E copy $ENV{DOTNET_SNK} .
    COMMENT "Copy or-tools.snk from ENV:DOTNET_SNK"
    WORKING_DIRECTORY dotnet
    VERBATIM
    )
else()
  set(OR_TOOLS_DOTNET_SNK CreateSigningKey)
  add_custom_command(OUTPUT dotnet/or-tools.snk
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${PROJECT_SOURCE_DIR}/ortools/dotnet/${OR_TOOLS_DOTNET_SNK} ${OR_TOOLS_DOTNET_SNK}
    COMMAND
    ${DOTNET_CLI} run
    --project ${OR_TOOLS_DOTNET_SNK}/${OR_TOOLS_DOTNET_SNK}.csproj
    /or-tools.snk
    COMMENT "Generate or-tools.snk using CreateSigningKey project"
    WORKING_DIRECTORY dotnet
    VERBATIM
    )
endif()

if(APPLE)
  set(RUNTIME_IDENTIFIER osx-x64)
elseif(UNIX)
  set(RUNTIME_IDENTIFIER linux-x64)
elseif(WIN32)
  set(RUNTIME_IDENTIFIER win-x64)
else()
  message(FATAL_ERROR "Unsupported system !")
endif()
set(OR_TOOLS_DOTNET_NATIVE ${OR_TOOLS_DOTNET}.runtime.${RUNTIME_IDENTIFIER})


file(GENERATE OUTPUT dotnet/replace_runtime.cmake
  CONTENT
  "FILE(READ ${PROJECT_SOURCE_DIR}/ortools/dotnet/${OR_TOOLS_DOTNET_NATIVE}/${OR_TOOLS_DOTNET_NATIVE}.csproj.in input)
STRING(REPLACE \"@PROJECT_VERSION@\" \"${PROJECT_VERSION}\" input \"\${input}\")
STRING(REPLACE \"@RUNTIME_IDENTIFIER@\" \"${RUNTIME_IDENTIFIER}\" input \"\${input}\")
STRING(REPLACE \"@OR_TOOLS_DOTNET@\" \"${OR_TOOLS_DOTNET}\" input \"\${input}\")
STRING(REPLACE \"@OR_TOOLS_DOTNET_NATIVE@\" \"${OR_TOOLS_DOTNET_NATIVE}\" input \"\${input}\")
STRING(REPLACE \"@ortools@\" \"$<TARGET_FILE:${PROJECT_NAME}>\" input \"\${input}\")
STRING(REPLACE \"@native@\" \"$<TARGET_FILE:google-ortools-native>\" input \"\${input}\")
FILE(WRITE ${OR_TOOLS_DOTNET_NATIVE}/${OR_TOOLS_DOTNET_NATIVE}.csproj \"\${input}\")"
)

add_custom_command(
  OUTPUT dotnet/${OR_TOOLS_DOTNET_NATIVE}/${OR_TOOLS_DOTNET_NATIVE}.csproj
  COMMAND ${CMAKE_COMMAND} -E make_directory ${OR_TOOLS_DOTNET_NATIVE}
  COMMAND ${CMAKE_COMMAND} -P $<$<BOOL:${GENERATOR_IS_MULTI_CONFIG}>:$<CONFIG>/>replace_runtime.cmake
  WORKING_DIRECTORY dotnet
  )

add_custom_target(dotnet_native ALL
  DEPENDS
    dotnet/or-tools.snk
    Dotnet${PROJECT_NAME}_proto
    google-ortools-native
    dotnet/${OR_TOOLS_DOTNET_NATIVE}/${OR_TOOLS_DOTNET_NATIVE}.csproj
  COMMAND ${CMAKE_COMMAND} -E make_directory packages
  COMMAND ${DOTNET_CLI} build -c Release /p:Platform=x64 ${OR_TOOLS_DOTNET_NATIVE}/${OR_TOOLS_DOTNET_NATIVE}.csproj
  COMMAND ${DOTNET_CLI} pack -c Release ${OR_TOOLS_DOTNET_NATIVE}/${OR_TOOLS_DOTNET_NATIVE}.csproj
  WORKING_DIRECTORY dotnet
  )


# Main Target
file(GENERATE OUTPUT dotnet/$<$<BOOL:${GENERATOR_IS_MULTI_CONFIG}>:$<CONFIG>/>replace.cmake
  CONTENT
  "FILE(READ ${PROJECT_SOURCE_DIR}/dotnet/${OR_TOOLS_DOTNET}.csproj.in input)
STRING(REPLACE \"@PROJECT_VERSION@\" \"${PROJECT_VERSION}\" input \"\${input}\")
STRING(REPLACE \"@OR_TOOLS_DOTNET@\" \"${OR_TOOLS_DOTNET}\" input \"\${input}\")
STRING(REPLACE \"@DOTNET_PACKAGES_DIR@\" \"${PROJECT_BINARY_DIR}/dotnet/packages\" input \"\${input}\")
FILE(WRITE ${OR_TOOLS_DOTNET}/${OR_TOOLS_DOTNET}.csproj \"\${input}\")"
)

add_custom_command(
  OUTPUT dotnet/${OR_TOOLS_DOTNET}/${OR_TOOLS_DOTNET}.csproj
  COMMAND ${CMAKE_COMMAND} -E make_directory ${OR_TOOLS_DOTNET}
  COMMAND ${CMAKE_COMMAND} -P $<$<BOOL:${GENERATOR_IS_MULTI_CONFIG}>:$<CONFIG>/>replace.cmake
  WORKING_DIRECTORY dotnet
  )

add_custom_target(dotnet_package ALL
  DEPENDS
    dotnet/or-tools.snk
    dotnet_native
    dotnet/${OR_TOOLS_DOTNET}/${OR_TOOLS_DOTNET}.csproj
  COMMAND ${DOTNET_CLI} build -c Release /p:Platform=x64 ${OR_TOOLS_DOTNET}/${OR_TOOLS_DOTNET}.csproj
  COMMAND ${DOTNET_CLI} pack -c Release ${OR_TOOLS_DOTNET}/${OR_TOOLS_DOTNET}.csproj
  BYPRODUCTS
    dotnet/packages
  WORKING_DIRECTORY dotnet
  )

# Test
if(BUILD_TESTING)
  #add_subdirectory(examples/dotnet)
endif()
