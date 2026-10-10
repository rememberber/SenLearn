#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Requires Xcode 16 or later."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent.parent
objects = []
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)
def refs(names):
    return '(' + ', '.join(uid(n) for n in names) + ',)'

targets = ['SenLearn', 'SenLearnTests', 'SenLearnUITests']
for name in targets:
    ext = 'app' if name == 'SenLearn' else 'xctest'
    product_type = 'application' if ext == 'app' else ('bundle.ui-testing' if name.endswith('UITests') else 'bundle.unit-test')
    add(name + 'Root', f'isa = PBXFileSystemSynchronizedRootGroup; path = {name}; sourceTree = "<group>";')
    add(name + 'Product', f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if ext == "app" else "wrapper.cfbundle"}; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
    for phase in ['Sources', 'Frameworks', 'Resources']:
        add(name + phase, f'isa = PBX{phase}BuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    dependencies = '()'
    if name != 'SenLearn':
        add(name + 'Proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("Project")}; proxyType = 1; remoteGlobalIDString = {uid("SenLearn")}; remoteInfo = SenLearn;')
        add(name + 'Dependency', f'isa = PBXTargetDependency; target = {uid("SenLearn")}; targetProxy = {uid(name + "Proxy")};')
        dependencies = refs([name + 'Dependency'])
    for config in ['Debug', 'Release']:
        settings = '''CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0;
        SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; TARGETED_DEVICE_FAMILY = "1,2";
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO;
        PRODUCT_NAME = "$(TARGET_NAME)"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'''
        settings += f'PRODUCT_BUNDLE_IDENTIFIER = com.senlearn.{"app" if name == "SenLearn" else name.lower()};'
        if name == 'SenLearn':
            settings += 'INFOPLIST_FILE = Config/Info.plist; GENERATE_INFOPLIST_FILE = NO; OTHER_LDFLAGS = "$(inherited) -lsqlite3";'
        else:
            settings += 'GENERATE_INFOPLIST_FILE = YES;'
            if name.endswith('UITests'):
                settings += 'TEST_TARGET_NAME = SenLearn;'
            else:
                settings += 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SenLearn.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SenLearn"; BUNDLE_LOADER = "$(TEST_HOST)";'
        add(name + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};')
    add(name + 'Configs', f'isa = XCConfigurationList; buildConfigurations = {refs([name + "Debug", name + "Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    add(name, f'''isa = PBXNativeTarget; name = {name}; productName = {name}; productReference = {uid(name + "Product")};
    productType = "com.apple.product-type.{product_type}"; buildConfigurationList = {uid(name + "Configs")};
    buildPhases = {refs([name + p for p in ['Sources', 'Frameworks', 'Resources']])};
    buildRules = (); dependencies = {dependencies}; fileSystemSynchronizedGroups = {refs([name + 'Root'])};''')

add('Products', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = {refs([n + "Product" for n in targets])};')
add('MainGroup', f'isa = PBXGroup; sourceTree = "<group>"; children = {refs([n + "Root" for n in targets] + ["Products"])};')
for config in ['Debug', 'Release']:
    settings = 'SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES;'
    settings += 'GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR; GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;'
    if config == 'Debug':
        settings += 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; ENABLE_TESTABILITY = YES; ONLY_ACTIVE_ARCH = YES; DEBUG_INFORMATION_FORMAT = dwarf;'
    else:
        settings += 'SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; VALIDATE_PRODUCT = YES;'
    add('Project' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};')
add('ProjectConfigs', f'isa = XCConfigurationList; buildConfigurations = {refs(["ProjectDebug", "ProjectRelease"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('Project', f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }};
buildConfigurationList = {uid('ProjectConfigs')}; compatibilityVersion = "Xcode 16.0"; developmentRegion = zh_CN;
knownRegions = (en, zh_CN, Base); mainGroup = {uid('MainGroup')}; productRefGroup = {uid('Products')};
projectDirPath = ""; projectRoot = ""; targets = {refs(targets)};''')
project = ROOT / 'SenLearn.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 77;\nobjects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("Project")};\n}}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
def ref(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name)}" BuildableName="{name}.{ "app" if name == "SenLearn" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:SenLearn.xcodeproj"/>'
(schemes / 'SenLearn.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('SenLearn')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
{''.join('<TestableReference skipped="NO">' + ref(n) + '</TestableReference>' for n in targets[1:])}
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('SenLearn')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref('SenLearn')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
