#!/usr/bin/env python3
"""Generates a clean, standalone MyLoc.xcodeproj linking MyLocCore and MyLocEngine.xcframework."""
import os
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ_DIR = os.path.join(ROOT, "MyLoc.xcodeproj")
os.makedirs(PROJ_DIR, exist_ok=True)

def uid(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()

swift_files = sorted([
    f for f in os.listdir(os.path.join(ROOT, "MyLocApp/Sources"))
    if f.endswith(".swift")
])

file_refs = []
build_files = []
source_build_ids = []
group_children = []

for f in swift_files:
    f_id = uid(f"fileref:{f}")
    b_id = uid(f"buildfile:{f}")
    file_refs.append(f'\t\t{f_id} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{f}"; path = "MyLocApp/Sources/{f}"; sourceTree = SOURCE_ROOT; }};')
    build_files.append(f'\t\t{b_id} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {f} */; }};')
    source_build_ids.append(f'\t\t\t\t{b_id} /* {f} in Sources */,')
    group_children.append(f'\t\t\t\t{f_id} /* {f} */,')

app_prod_id = uid("product:MyLoc.app")
info_plist_id = uid("fileref:Info.plist")
assets_ref_id = uid("fileref:Assets.xcassets")
assets_build_id = uid("buildfile:Assets.xcassets")
xcfw_ref_id = uid("fileref:MyLocEngine.xcframework")
xcfw_build_id = uid("buildfile:MyLocEngine.xcframework")
pkg_ref_id = uid("pkgref:MyLocCore")
pkg_prod_id = uid("pkgprod:MyLocCore")
pkg_build_id = uid("buildfile:MyLocCore")

main_group_id = uid("group:main")
sources_group_id = uid("group:sources")
frameworks_group_id = uid("group:frameworks")
products_group_id = uid("group:products")

sources_phase_id = uid("phase:sources")
frameworks_phase_id = uid("phase:frameworks")
resources_phase_id = uid("phase:resources")

target_id = uid("target:MyLoc")
project_id = uid("project:MyLoc")

proj_cfg_list_id = uid("cfglist:project")
proj_debug_id = uid("cfg:project:debug")
proj_release_id = uid("cfg:project:release")

tgt_cfg_list_id = uid("cfglist:target")
tgt_debug_id = uid("cfg:target:debug")
tgt_release_id = uid("cfg:target:release")

pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
\t\t{assets_build_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref_id} /* Assets.xcassets */; }};
\t\t{xcfw_build_id} /* MyLocEngine.xcframework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {xcfw_ref_id} /* MyLocEngine.xcframework */; }};
\t\t{pkg_build_id} /* MyLocCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {pkg_prod_id} /* MyLocCore */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{app_prod_id} /* MyLoc.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MyLoc.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{info_plist_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = Info.plist; path = MyLocApp/Resources/Info.plist; sourceTree = SOURCE_ROOT; }};
\t\t{assets_ref_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = Assets.xcassets; path = MyLocApp/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT; }};
\t\t{xcfw_ref_id} /* MyLocEngine.xcframework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = MyLocEngine.xcframework; path = Frameworks/MyLocEngine.xcframework; sourceTree = SOURCE_ROOT; }};
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase_id} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{pkg_build_id} /* MyLocCore in Frameworks */,
\t\t\t\t{xcfw_build_id} /* MyLocEngine.xcframework in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group_id} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{sources_group_id} /* Sources */,
\t\t\t\t{info_plist_id} /* Info.plist */,
\t\t\t\t{assets_ref_id} /* Assets.xcassets */,
\t\t\t\t{frameworks_group_id} /* Frameworks */,
\t\t\t\t{products_group_id} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{sources_group_id} /* Sources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(group_children)}
\t\t\t);
\t\t\tname = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{frameworks_group_id} /* Frameworks */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{xcfw_ref_id} /* MyLocEngine.xcframework */,
\t\t\t);
\t\t\tname = Frameworks;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group_id} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_prod_id} /* MyLoc.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* MyLoc */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {tgt_cfg_list_id} /* Build configuration list for PBXNativeTarget "MyLoc" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase_id} /* Sources */,
\t\t\t\t{frameworks_phase_id} /* Frameworks */,
\t\t\t\t{resources_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = MyLoc;
\t\t\tpackageProductDependencies = (
\t\t\t\t{pkg_prod_id} /* MyLocCore */,
\t\t\t);
\t\t\tproductName = MyLoc;
\t\t\tproductReference = {app_prod_id} /* MyLoc.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tbuildConfigurationList = {proj_cfg_list_id} /* Build configuration list for PBXProject "MyLoc" */;
\t\t\tcompatibilityVersion = "Xcode 15.0";
\t\t\tdevelopmentRegion = "zh-Hans";
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\t"zh-Hans",
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tpackageReferences = (
\t\t\t\t{pkg_ref_id} /* XCLocalSwiftPackageReference "MyLocCore" */,
\t\t\t);
\t\t\tproductRefGroup = {products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* MyLoc */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase_id} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{assets_build_id} /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(source_build_ids)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{proj_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{proj_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{tgt_debug_id} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = MyLocApp/Resources/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.myloc.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{tgt_release_id} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = MyLocApp/Resources/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.myloc.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{proj_cfg_list_id} /* Build configuration list for PBXProject "MyLoc" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{proj_debug_id} /* Debug */,
\t\t\t\t{proj_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{tgt_cfg_list_id} /* Build configuration list for PBXNativeTarget "MyLoc" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{tgt_debug_id} /* Debug */,
\t\t\t\t{tgt_release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{pkg_ref_id} /* XCLocalSwiftPackageReference "MyLocCore" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = MyLocCore;
\t\t}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{pkg_prod_id} /* MyLocCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {pkg_ref_id} /* XCLocalSwiftPackageReference "MyLocCore" */;
\t\t\tproductName = MyLocCore;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
"""

with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w", encoding="utf-8") as f:
    f.write(pbx)

print(f"Generated {PROJ_DIR}/project.pbxproj with {len(swift_files)} Swift files.")
