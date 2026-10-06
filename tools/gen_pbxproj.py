#!/usr/bin/env python3
"""Generate DailyBoxScore.xcodeproj/project.pbxproj for the app sources."""
import os
import uuid

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(BASE, "DailyBoxScore")

SOURCES = [
    "DailyBoxScoreApp.swift",
    "Models/MLBTeam.swift",
    "Models/FeedModels.swift",
    "Services/FeedService.swift",
    "Services/FavoritesStore.swift",
    "Services/NotificationManager.swift",
    "Services/StoreManager.swift",
    "Views/ContentView.swift",
    "Views/EditionDetailView.swift",
    "Views/PDFReaderView.swift",
    "Views/MyTeamsView.swift",
    "Views/SettingsView.swift",
    "Views/VintageTheme.swift",
]
RESOURCES = ["Assets.xcassets"]
# Referenced but not part of any build phase:
AUX = ["Info.plist", "Configuration.storekit"]


def new_id():
    return uuid.uuid4().hex[:24].upper()


def fileref(name, path, ftype, source_tree="<group>"):
    return (f"{new_id()} = {{isa = PBXFileReference; "
            f"lastKnownFileType = {ftype}; name = {name}; path = {path}; "
            f"sourceTree = \"{source_tree}\"; }};")


def main():
    build_files = {}
    file_refs = {}
    for src in SOURCES:
        name = os.path.basename(src)
        fid = new_id()
        bid = new_id()
        file_refs[fid] = (f"{fid} = {{isa = PBXFileReference; "
                          f"lastKnownFileType = sourcecode.swift; "
                          f"path = {src}; sourceTree = \"<group>\"; }};")
        build_files[bid] = (f"{bid} = {{isa = PBXBuildFile; fileRef = {fid}; }};")

    res_refs = {}
    res_build = {}
    for res in RESOURCES:
        fid = new_id()
        bid = new_id()
        res_refs[fid] = (f"{fid} = {{isa = PBXFileReference; "
                         f"lastKnownFileType = folder.assetcatalog; "
                         f"path = {res}; sourceTree = \"<group>\"; }};")
        res_build[bid] = f"{bid} = {{isa = PBXBuildFile; fileRef = {fid}; }};"

    aux_refs = {}
    for a in AUX:
        fid = new_id()
        ftype = ("text.plist.xml" if a.endswith(".plist")
                 else "text.json")
        aux_refs[fid] = (f"{fid} = {{isa = PBXFileReference; "
                         f"lastKnownFileType = {ftype}; path = {a}; "
                         f'sourceTree = "<group>"; }};')

    app_ref = new_id()
    app_fileref = (f"{app_ref} = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
                   f'includeInIndex = 0; path = DailyBoxScore.app; sourceTree = BUILT_PRODUCTS_DIR; }};')

    # Groups
    def group(name, children, path=None):
        gid = new_id()
        kids = "\n".join(f"\t\t\t\t{child}," for child in children)
        p = f'path = {path}; ' if path else ''
        return gid, (f"{gid} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{kids}\n\t\t\t);\n"
                     f"\t\t\t{name and ('name = ' + name + '; ') or ''}{p}sourceTree = \"<group>\";\n\t\t}};")

    src_ids = list(file_refs) + list(res_refs) + list(aux_refs)
    models_ids = [fid for fid, s in zip(file_refs, SOURCES) if s.startswith("Models/")]
    services_ids = [fid for fid, s in zip(file_refs, SOURCES) if s.startswith("Services/")]
    views_ids = [fid for fid, s in zip(file_refs, SOURCES) if s.startswith("Views/")]
    top_ids = [fid for fid, s in zip(file_refs, SOURCES) if "/" not in s]

    models_gid, models_grp = group("Models", models_ids)
    services_gid, services_grp = group("Services", services_ids)
    views_gid, views_grp = group("Views", views_ids)
    app_gid, app_grp = group("DailyBoxScore",
                             top_ids + [models_gid, services_gid, views_gid]
                             + list(res_refs) + list(aux_refs),
                             path="DailyBoxScore")
    products_gid, products_grp = group("Products", [app_ref])
    main_gid, main_grp = group(None, [app_gid, products_gid])

    # Build phases
    sources_phase = new_id()
    resources_phase = new_id()
    frameworks_phase = new_id()
    src_files = "\n".join(f"\t\t\t\t{bid}," for bid in build_files)
    res_files = "\n".join(f"\t\t\t\t{bid}," for bid in res_build)

    # Target / project / configs
    target_id = new_id()
    project_id = new_id()
    target_cfg_list = new_id()
    project_cfg_list = new_id()
    dbg_t, rel_t = new_id(), new_id()
    dbg_p, rel_p = new_id(), new_id()

    target_cfg = f"""\
{dbg_t} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tINFOPLIST_FILE = DailyBoxScore/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.toolstem.dailyboxscore;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
{rel_t} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tINFOPLIST_FILE = DailyBoxScore/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.toolstem.dailyboxscore;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};"""

    project_cfg = f"""\
{dbg_p} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
{rel_p} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};"""

    pbxproj = f"""\
// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files.values())}
{chr(10).join(res_build.values())}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{app_fileref}
{chr(10).join(file_refs.values())}
{chr(10).join(res_refs.values())}
{chr(10).join(aux_refs.values())}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{main_grp}
{app_grp}
{models_grp}
{services_grp}
{views_grp}
{products_grp}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_cfg_list};
\t\t\tbuildPhases = (
\t\t\t\t{frameworks_phase},
\t\t\t\t{resources_phase},
\t\t\t\t{sources_phase},
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = DailyBoxScore;
\t\t\tproductName = DailyBoxScore;
\t\t\tproductReference = {app_ref};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t}};
\t\t\tbuildConfigurationList = {project_cfg_list};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_gid};
\t\t\tproductRefGroup = {products_gid};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id},
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{res_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{target_cfg}
{project_cfg}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{target_cfg_list} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{dbg_t},
\t\t\t\t{rel_t},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{project_cfg_list} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{dbg_p},
\t\t\t\t{rel_p},
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id};
}}
"""

    out_dir = os.path.join(BASE, "DailyBoxScore.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "project.pbxproj"), "w") as f:
        f.write(pbxproj)
    print(f"Wrote {out_dir}/project.pbxproj")
    return target_id


if __name__ == "__main__":
    main()
