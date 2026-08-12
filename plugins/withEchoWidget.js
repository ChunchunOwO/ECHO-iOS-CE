const fs = require('fs');
const path = require('path');
const { withDangerousMod, withXcodeProject } = require('@expo/config-plugins');

const targetName = 'EchoWidget';

module.exports = (config) => {
  config = withDangerousMod(config, ['ios', async (mod) => {
    const source = path.join(mod.modRequest.projectRoot, 'targets', targetName);
    const destination = path.join(mod.modRequest.platformProjectRoot, targetName);
    fs.mkdirSync(destination, { recursive: true });
    for (const name of ['EchoWidget.swift', 'EchoWidget-Info.plist', 'EchoWidget.entitlements']) {
      fs.copyFileSync(path.join(source, name), path.join(destination, name));
    }
    return mod;
  }]);

  return withXcodeProject(config, (mod) => {
    const project = mod.modResults;
    if (project.pbxTargetByName(targetName)) return mod;

    const bundleIdentifier = `${mod.ios?.bundleIdentifier || 'app.echo.next.ios'}.widget`;
    const target = project.addTarget(targetName, 'app_extension', targetName, bundleIdentifier);
    project.addBuildPhase([], 'PBXSourcesBuildPhase', 'Sources', target.uuid);
    project.addBuildPhase([], 'PBXFrameworksBuildPhase', 'Frameworks', target.uuid);
    const group = project.addPbxGroup([], targetName, targetName);
    project.addToPbxGroup(group.uuid, project.getFirstProject().firstProject.mainGroup);
    project.addSourceFile('EchoWidget.swift', { target: target.uuid }, group.uuid);
    project.addFile('EchoWidget-Info.plist', group.uuid);
    project.addFile('EchoWidget.entitlements', group.uuid);

    const configurationList = project.pbxXCConfigurationList()[target.pbxNativeTarget.buildConfigurationList];
    const configurations = project.pbxXCBuildConfigurationSection();
    for (const item of configurationList.buildConfigurations) {
      const settings = configurations[item.value].buildSettings;
      settings.APPLICATION_EXTENSION_API_ONLY = 'YES';
      settings.CODE_SIGN_ENTITLEMENTS = '"EchoWidget/EchoWidget.entitlements"';
      settings.CURRENT_PROJECT_VERSION = '1';
      settings.IPHONEOS_DEPLOYMENT_TARGET = '15.1';
      settings.MARKETING_VERSION = '1.5.1';
      settings.SWIFT_VERSION = '5.0';
      settings.TARGETED_DEVICE_FAMILY = '"1,2"';
    }
    return mod;
  });
};
