function kay1024_phase_blackbox_config(this_block)
% Pure Verilog sources; no unresolved CORDIC/IP dependencies in this Black Box.
this_block.setTopLevelLanguage('Verilog');
this_block.setEntityName('kay1024_phase_blackbox');
this_block.addSimulinkInport('valid_in');
for lane=0:7, this_block.addSimulinkInport(sprintf('phase%d',lane)); end
this_block.addSimulinkOutport('freq_q20');
this_block.port('freq_q20').setType('Fix_32_20');
if this_block.inputTypesKnown
    for name={'valid_in'}
        this_block.port(name{1}).useHDLVector(false);
        if ~strcmp(this_block.port(name{1}).type,'Bool')
            this_block.setError([name{1} ' must be Boolean.']); return;
        end
    end
    for lane=0:7
        if ~strcmp(this_block.port(sprintf('phase%d',lane)).type,'Fix_30_18')
            this_block.setError('Phase inputs must be Fix_30_18 radians from Subsystem16 before Fs/2/pi.'); return;
        end
    end
end
if this_block.inputRatesKnown
    rates=unique(this_block.inputRates);
    rates=rates(isfinite(rates));
    if numel(rates)~=1
        this_block.setError('All inputs must share one synchronous sample rate.'); return;
    end
    this_block.addClkCEPair('clk','ce',rates(1));
    this_block.port('freq_q20').setRate(rates(1));
end
here=fileparts(mfilename('fullpath'));
this_block.clearSrcFiles;
for source={'rtl/kay_phase_core.v','rtl/kay_sum_to_mhz.v','kay1024_phase_blackbox.v'}
    this_block.addFile(fullfile(here,source{1}));
end
end
