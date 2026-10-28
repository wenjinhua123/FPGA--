% Run from MATLAB launched with Model Composer 2022.2.
here=fileparts(mfilename('fullpath'));
addpath(here,fullfile(here,'tools'));
cd(here);
kay_demo_init;
load_system(fullfile(here,'kay1024_recursive_demo.slx'));
% Repoint visible and saved Hub settings when this folder is copied.
sync_sysgen_hub('kay1024_recursive_demo/Vitis Model Composer Hub',...
    fullfile(here,'build','sysgen'));
open_system(fullfile(here,'kay1024_recursive_demo.slx'));
