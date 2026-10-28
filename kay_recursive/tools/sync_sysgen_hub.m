function sync_sysgen_hub(hub, output_directory)
% Synchronize visible and persistent 2022.2 Hub settings for the whole model.
% Saving a model under a new name does not rewrite legacy saved/App Designer
% target settings; update both so UI and programmatic exports agree.
model = bdroot(hub);
if nargin < 2
    project = fileparts(fileparts(mfilename('fullpath')));
    output_directory = fullfile(project, 'build', 'sysgen');
end
if ~isfolder(output_directory), mkdir(output_directory); end
ip_name = 'kay1024_recursive';
set_param(hub, 'simulink_period', '1', 'sysclk_period', '3.2', ...
    'ClockFrequency', '312.5', 'directory', output_directory, ...
    'TargetDirectory', output_directory, 'testbench', 'off');
info.HDLSubsystem = struct('SubsystemName', model, 'IPName', ip_name, ...
    'IPLibrary', 'user', 'IPVendor', 'user', 'IPVersion', '1.0');
set_param(hub, 'IPInfoJsonString', jsonencode(info));
data = get_param(hub, 'UserData');
assert(data.isLegacyHDLDesign == 1, 'Expected the preserved original HDL Hub.');
data.saved.shared.simulink_period = '1';
target_name = data.saved.shared.compilation;
target = data.saved.compilation.(target_name);
target.subsystem = model;
target.directory = output_directory;
target.sysclk_period = '3.2';
target.testbench = 'off';
target.synthesis_language = 'Verilog';
target.xlIPsettingsdata = update_ip(target.xlIPsettingsdata, output_directory, ip_name);
data.saved.compilation.(target_name) = target;
data.appInfo.codeDirectory = output_directory;
node_keys = data.appInfo.nodeDataMap.keys;
assert(any(strcmp(node_keys, '0')), 'The original root HDL target is missing.');
node = data.appInfo.nodeDataMap('0');
node.codeDirectory = output_directory;
node.simulinkSystemPeriod = '1';
node.fpgaClockPeriod = '3.2';
node.hardwareDescription = 'Verilog';
node.createTestbench = false;
node.ipSettings = update_ip(node.ipSettings, output_directory, ip_name);
data.appInfo.nodeDataMap('0') = node;
data.appInfo.dutTree.checkedNodes = {'0'};
data.appInfo.dutTree.checkedNodesTag = {'HDLNode'};
data.appInfo.dutTree.selectedNodes = {'0'};
set_param(hub, 'UserData', data);
end

function ip = update_ip(ip, output_directory, name)
ip.IP_Vendor_Text = 'user';
ip.IP_Library_Text = 'user';
ip.IP_Name_Text = name;
ip.IP_Version_Text = '1.0';
ip.IP_Common_Repos = false;
ip.IP_Dir = output_directory;
end
