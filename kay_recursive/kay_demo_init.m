function kay_demo_init
% Default deterministic stimulus. Set kay_use_custom_inputs=true to supply
% sig_re0..7, sig_im0..7 and kay_reset_signal yourself (period = 1).
if evalin('base','exist(''kay_use_custom_inputs'',''var'') && kay_use_custom_inputs'), return; end
groups=700; reset_cycles=0;
n=(0:8*(groups-reset_cycles)-1)';
frequency=170+450*sin(n/211)+75*cos(n/29);
phase=cumsum(2*pi*frequency/2500);
iq=0.75*exp(1i*phase);
iq=round(real(iq)*8192)/8192+1i*round(imag(iq)*8192)/8192;
for lane=0:7
    assignin('base',sprintf('sig_re%d',lane),[zeros(reset_cycles,1);real(iq(lane+1:8:end))]);
    assignin('base',sprintf('sig_im%d',lane),[zeros(reset_cycles,1);imag(iq(lane+1:8:end))]);
end
assignin('base','kay_demo_iq',iq);
assignin('base','kay_demo_reset_cycles',reset_cycles);
end
