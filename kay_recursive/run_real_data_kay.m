% 实测、模拟100MHz、模拟线性调频：SysGen输出 vs MATLAB标准Kay。
here=fileparts(mfilename('fullpath'));
groups=1024;               % 每组8点；只取实测数据前8192点，缩短联合仿真时间
Fs=2500; reset_cycles=0; snr_db=10; flush_groups=64;

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

for dataset=1:3
    if dataset==1, iq=real_iq; name='实测数据';
    elseif dataset==2, iq=sim_iq; name='模拟100MHz';
    else
        n=(0:19999).';
        chirp_mhz=-1000+2000*n/19999;
        iq=exp(1i*2*pi*cumsum(chirp_mhz)/Fs);
        name='模拟线性调频 -1000 到 1000 MHz';
    end
    test_groups=numel(iq)/8;
    % 统一缩放并量化到模型输入的Fix14_13范围。
    iq=0.75*iq/max(abs(iq));
    iq=complex(round(real(iq)*8192),round(imag(iq)*8192))/8192;
    % 停止送入测试数据后继续仿真，让前端和Kay的流水线排空。
    % 追加样本产生的窗口不计入比较。
    iq_drive=[iq;complex(zeros(8*flush_groups,1))];
    for lane=0:7
        assignin('base',sprintf('sig_re%d',lane),...
            [zeros(reset_cycles,1);real(iq_drive(lane+1:8:end))]);
        assignin('base',sprintf('sig_im%d',lane),...
            [zeros(reset_cycles,1);imag(iq_drive(lane+1:8:end))]);
    end
    t=(0:test_groups+flush_groups-1).';
    result=sim('kay1024_recursive_demo','StopTime',num2str(t(end)),...
        'ReturnWorkspaceOutputs','on');
    freq_trace=result.get('kay_freq_q20');
    model_mhz=double(freq_trace.Data);
    first=find(isfinite(model_mhz) & model_mhz~=0,1);
    assert(~isempty(first) && freq_trace.Time(first)>=127,...
        '首个完整Kay窗口未产生频率');
    model_mhz=model_mhz(first:end);
    count=test_groups-127;
    assert(numel(model_mhz)>=count,'排空后仍缺少完整Kay窗口结果');
    model_mhz=model_mhz(1:count);
    assert(all(isfinite(model_mhz)),'模型输出无效');

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
    if dataset==3
        err=model_mhz(:)-matlab_mhz(:);
        fprintf('  首窗 SysGen %.6f / MATLAB %.6f MHz；末窗 %.6f / %.6f MHz\n',...
            model_mhz(1),matlab_mhz(1),model_mhz(end),matlab_mhz(end));
        fprintf('  与MATLAB Kay逐窗最大差 %.6f MHz，平均差 %.6f MHz\n',...
            max(abs(err)),mean(err));
    end
end
assignin('base','kay_use_custom_inputs',false);
