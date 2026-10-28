% 实测数据和模拟100MHz：SysGen输出 vs MATLAB标准Kay（均值MHz，方差MHz^2）。
here=fileparts(mfilename('fullpath'));
groups=1024;               % 每组8点；只取实测数据前8192点，缩短联合仿真时间
Fs=2500; reset_cycles=4; snr_db=10;

fid=fopen(fullfile(here,'data_10dB_100MHz.dat'),'r','ieee-le');
assert(fid>0,'找不到实测I/Q文件');
raw=fread(fid,[2,8*groups],'int16=>double'); fclose(fid);
assert(size(raw,2)==8*groups,'实测数据不足');
real_iq=complex(raw(1,:).',raw(2,:).');

old_rng=rng; rng(1);
n=(0:8*groups-1).';
sim_iq=exp(1i*2*pi*100/Fs*n)+...
    (randn(size(n))+1i*randn(size(n)))/sqrt(2*10^(snr_db/10));
rng(old_rng);

assignin('base','kay_use_custom_inputs',true);
run(fullfile(here,'open_kay_demo.m')); % 打开已有SysGen模型及Black Box配置

for dataset=1:2
    if dataset==1, iq=real_iq; name='实测数据';
    else, iq=sim_iq; name='模拟100MHz'; end
    % 统一缩放并量化到模型输入的Fix14_13范围。
    iq=0.75*iq/max(abs(iq));
    iq=complex(round(real(iq)*8192),round(imag(iq)*8192))/8192;
    for lane=0:7
        assignin('base',sprintf('sig_re%d',lane),...
            [zeros(reset_cycles,1);real(iq(lane+1:8:end))]);
        assignin('base',sprintf('sig_im%d',lane),...
            [zeros(reset_cycles,1);imag(iq(lane+1:8:end))]);
    end
    t=(0:groups+reset_cycles-1).';
    assignin('base','kay_reset_signal',[t double(t<reset_cycles)]);
    result=sim('kay1024_recursive_demo','StopTime',num2str(t(end)),...
        'ReturnWorkspaceOutputs','on');
    model_mhz=double(result.get('kay_freq_q20').Data);
    valid=double(result.get('kay_valid').Data)==1;
    model_mhz=model_mhz(valid);
    count=numel(model_mhz);
    assert(count>1,'SysGen没有产生有效频率输出');
    assert(all(isfinite(model_mhz)) && count<=groups-127,'模型输出无效或窗口数量不匹配');

    % 与模型同一批1024点窗口：首窗1:1024，后续每次前进8点。
    phase=angle(conj(iq(1:end-1)).*iq(2:end));
    weight=(1:1023).*(1024-(1:1023));
    index=(0:1022)'+(1:8:8*count);
    matlab_mhz=(weight*phase(index)).'*Fs/(2*pi*sum(weight));
    fprintf('%s：\n',name);
    fprintf('  SysGen Kay  均值 %.9f MHz，方差 %.9g MHz^2\n',...
        mean(model_mhz),var(model_mhz));
    fprintf('  MATLAB Kay 均值 %.9f MHz，方差 %.9g MHz^2\n',...
        mean(matlab_mhz),var(matlab_mhz));
end
assignin('base','kay_use_custom_inputs',false);
