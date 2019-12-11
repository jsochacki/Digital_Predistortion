clear all
clc

%file and settings
file = './Test_Results/40dBm_2p5GHz_QPSK_8x_oversampling_6p25_alpha_200ksymbols_NO_AWGN_7dB_PAPR.mat';
MODCOD = 1; %QPSK
% file = './Test_Results/40dBm_2p5GHz_APSK32_8x_oversampling_6p25_alpha_200ksymbols_NO_AWGN_8dB_PAPR.mat';
% MODCOD = 13; %32 APSK
% file = './Test_Results/40dBm_2p5GHz_DVBT2_16QAM_8x_oversampling_6p25_alpha_200ksymbols_NO_AWGN_8dB_PAPR.mat';
% MODCOD = 19; %DVBT2 16 QAM

% baseband_oversampling_rate = 4;
% channel_bandwidth = 50e6;

baseband_oversampling_rate = 8;
channel_bandwidth = 25e6;

%search_length = baseband_oversampling_rate * (channel_bandwidth / 25e6);

set_carrier_frequency = 2.5e9;
channel_1_set_sample_rate = 40e9;
channel_2_set_sample_rate = 40e9;
channel_1_set_sample_time_window = 50e-6;
channel_2_set_sample_time_window = 50e-6;
channel_1_set_time_resolution = 1 / channel_1_set_sample_rate;
channel_2_set_time_resolution = 1 / channel_2_set_sample_rate;
channel_1_set_voltage_range = 0.04;
channel_2_set_voltage_range = 1.6;
channel_1_set_voltage_resolution_in_bits = 16;
channel_2_set_voltage_resolution_in_bits = 16;
channel_1_set_minimum_ENOB = 9;
channel_2_set_minimum_ENOB = 9;

%Generate constellation
[Complex_Alphabet Binary_Alphabet Decimal_Alphabet BITS_PER_WORD] = dvbs2_Constellations(MODCOD);

%Load data and calculate derived and actual values
dataset = load('-mat', file);
channel_1_calculated_sample_time_window = dataset.Channel_1.XDispRange;
channel_2_calculated_sample_time_window = dataset.Channel_2.XDispRange;
channel_1_number_of_samples = dataset.Channel_1.NumPoints;
channel_2_number_of_samples = dataset.Channel_2.NumPoints;
channel_1_waveform_int16 = dataset.Channel_1.Data;
channel_2_waveform_int16 = dataset.Channel_2.Data;

t = 0:channel_1_set_time_resolution:(channel_1_set_time_resolution * (channel_1_number_of_samples - 1));

channel_1_calculated_sample_rate = channel_1_number_of_samples / channel_1_calculated_sample_time_window;
channel_2_calculated_sample_rate = channel_2_number_of_samples / channel_2_calculated_sample_time_window;

channel_1_calculated_ENOB = log2(dataset.Channel_1.YDispRange/dataset.Channel_1.YInc);
channel_2_calculated_ENOB = log2(dataset.Channel_2.YDispRange/dataset.Channel_2.YInc);

channel_1_calculated_voltage_resolution_in_bits = channel_1_calculated_ENOB;
channel_2_calculated_voltage_resolution_in_bits = channel_2_calculated_ENOB;

channel_1_calculated_voltage_resolution = dataset.Channel_1.YInc;
channel_2_calculated_voltage_resolution = dataset.Channel_2.YInc;

channel_1_waveform = double(channel_1_waveform_int16) / (2^(channel_1_set_voltage_resolution_in_bits));
channel_2_waveform = double(channel_2_waveform_int16) / (2^(channel_1_set_voltage_resolution_in_bits));

%Convert to baseband
channel_1_baseband_waveform = channel_1_waveform .* exp(-j*2*pi*set_carrier_frequency*t).';
channel_2_baseband_waveform = channel_2_waveform .* exp(-j*2*pi*set_carrier_frequency*t).';

%Filter
oversampling_rate = channel_1_set_sample_rate / channel_bandwidth;
resampling_ratio = oversampling_rate / baseband_oversampling_rate;
h = fir1(2^14, 1 / resampling_ratio).';
temp_1 = cconv(channel_1_baseband_waveform, h);
temp_1 = temp_1((1+((length(h) - 1) / 2)):1:end-((length(h) - 1) / 2));
temp_2 = cconv(channel_2_baseband_waveform, h);
temp_2 = temp_2((1+((length(h) - 1) / 2)):1:end-((length(h) - 1) / 2));

%Generate RX filter
filter_alpha = 0.0625;
filter_length_in_symbols = 48;
filter_implementation_type = 'firrcoswu';

filter_half_filter_length_at_design_rate = (filter_length_in_symbols .* baseband_oversampling_rate) / 2;
ringing_length = filter_half_filter_length_at_design_rate;

[filter_h, result] = generate_srrc_filter(filter_implementation_type, ...
                                          filter_length_in_symbols, ...
                                          filter_alpha, ...
                                          baseband_oversampling_rate);

%Makes unity gain filter
filter_h = (filter_h ./ sqrt(sum(power(filter_h, 2)))).';

%Downsample
channel_1_baseband_waveform = downsample(temp_1, resampling_ratio);
channel_2_baseband_waveform = downsample(temp_2, resampling_ratio);

%receive
temp_1 = cconv(channel_1_baseband_waveform, filter_h);
temp_1 = temp_1(1+(ringing_length):1:end-(ringing_length));
temp_2 = cconv(channel_2_baseband_waveform, filter_h);
temp_2 = temp_2(1+(ringing_length):1:end-(ringing_length));


%First get proper symbol timing per current oversampling ratio
symbol_power = zeros(1, (baseband_oversampling_rate - 1));
for n = 1:1:(baseband_oversampling_rate - 1)
   symbol_power(n) = var(downsample(temp_1(n:end), baseband_oversampling_rate));
end

offset_1 = find(symbol_power == max(symbol_power));

%First get proper symbol timing per current oversampling ratio
symbol_power = zeros(1, (baseband_oversampling_rate - 1));
for n = 1:1:(baseband_oversampling_rate - 1)
   symbol_power(n) = var(downsample(temp_2(n:end), baseband_oversampling_rate));
end

offset_2 = find(symbol_power == max(symbol_power));

%Downsample
channel_1_symbols = downsample(temp_1(offset_1:end), baseband_oversampling_rate);
channel_2_symbols = downsample(temp_2(offset_2:end), baseband_oversampling_rate);
difference = (length(channel_2_symbols) - length(channel_1_symbols));
if difference >= 0
   channel_2_symbols = channel_2_symbols((1+difference):end);
elseif difference < 0
   channel_1_symbols = channel_1_symbols((1+abs(difference)):end);
end

%Normalize Power for signal metrics
channel_1_symbols_normalized = (mean(abs(Complex_Alphabet))).*channel_1_symbols./mean(abs(channel_1_symbols));
channel_2_symbols_normalized = (mean(abs(Complex_Alphabet))).*channel_2_symbols./mean(abs(channel_2_symbols));

%Do Phase Alignment
%First step is get the relative phase difference between the tx and rx
%signals
N = length(channel_1_symbols_normalized);
phases = 0:1:359;
error = zeros(1, length(phases));
for n = 1:1:length(phases)
   temp = (channel_1_symbols_normalized.*exp(-j*phases(n)*(pi/180))) ...
           - channel_2_symbols_normalized;
   error(n) = (temp'*temp) / N;
end

%Negative since im rotating channel 1 but applying to 2
channel_1_to_channel_2_phase_delta = -phases(find(error == min(error)));

%Second step is get the relative phase difference between the tx and the
%ideal consteallation
N = length(channel_1_symbols_normalized);
phases = 0:1:89;
error = zeros(1, length(phases));
for n = 1:1:length(phases)
   for nn = 1:1:N
      temp = (channel_1_symbols_normalized(nn).*exp(-j*phases(n)*(pi/180)))...
             - Complex_Alphabet;
      error(n) = error(n) + min(temp.*temp'.');
   end
end

channel_1_to_ideal_phase_delta = phases(find(error == min(error)));

channel_1_phase_shift = channel_1_to_ideal_phase_delta;
channel_2_phase_shift = channel_1_phase_shift + channel_1_to_channel_2_phase_delta;

%For pre-distortion
channel_1_baseband_waveform_relative = channel_1_baseband_waveform.*exp(-j*channel_1_phase_shift*(pi/180));
channel_2_baseband_waveform_relative = channel_2_baseband_waveform.*exp(-j*channel_2_phase_shift*(pi/180));

%For Reception
channel_1_symbols_normalized_relative = (channel_1_symbols_normalized.*exp(-j*channel_1_phase_shift*(pi/180)));
channel_2_symbols_normalized_relative = (channel_2_symbols_normalized.*exp(-j*channel_2_phase_shift*(pi/180)));

[channel_1_decoded_complex_stream] = AWGN_maximum_likelyhood_decoder(channel_1_symbols_normalized_relative, Complex_Alphabet, Complex_Alphabet);
[channel_2_decoded_complex_stream] = AWGN_maximum_likelyhood_decoder(channel_2_symbols_normalized_relative, Complex_Alphabet, Complex_Alphabet);

channel_1_symbols_normalized_relative = channel_1_symbols_normalized_relative(1:end-2);
channel_1_decoded_complex_stream = channel_1_decoded_complex_stream(1:end-2);
channel_2_symbols_normalized_relative = channel_2_symbols_normalized_relative(1:end-2);
channel_2_decoded_complex_stream = channel_2_decoded_complex_stream(1:end-2);

SNR_dB_before_PA = Measure_SNR(channel_1_symbols_normalized_relative, channel_1_decoded_complex_stream);
EVM_percent_before_PA = 100*sqrt(1/power(10,SNR_dB_before_PA/10));
SNR_dB_after_PA = Measure_SNR(channel_2_symbols_normalized_relative, channel_2_decoded_complex_stream);
EVM_percent_after_PA = 100*sqrt(1/power(10,SNR_dB_after_PA/10));

%Train Memory Polynomial Model for PA
PREDISTORTER_BACKOFF = 0;
CFR = 0;
CFR_Iterations = 100;
PAPR_Reduction = 1;
QPA = 5; %must be odd
PA_POLYNOMIAL_ORDER = 3;
QPD = 5; %must be odd
DPD_POLYNOMIAL_ORDER = 3;

pa_coefficients_with_memory = Memory_Polynomial_Solution(channel_2_baseband_waveform_relative, channel_1_baseband_waveform_relative, PA_POLYNOMIAL_ORDER, QPA);

%FIND SS GAIN
lin_input = channel_1_baseband_waveform_relative * power(10, -30/10); %Take input down by 30 dB to linear point
ssvout = Memory_Polynomial_Amplifier(lin_input, pa_coefficients_with_memory, PA_POLYNOMIAL_ORDER, QPA);
SYSTEM_POWER_GAIN_dB = 10*log10((ssvout'*ssvout)/(lin_input'*lin_input));

%Now solve for a single itteration of the memory prolynomial predistorter
if CFR
   pre_CFR_PAPR = PAPR_dB(channel_1_baseband_waveform_relative, []);
   [pd_tx_waveform_post_cfr post_CFR_PAPR] = serial_peak_cancellation(channel_1_baseband_waveform_relative, filter_h, pre_CFR_PAPR - PAPR_Reduction, CFR_Iterations);
   training_signal = pd_tx_waveform_post_cfr;
else
   training_signal = channel_1_baseband_waveform_relative;
end
tx_waveform_at_pa_output_pd = Memory_Polynomial_Amplifier(training_signal, pa_coefficients_with_memory, PA_POLYNOMIAL_ORDER, QPA);
tx_waveform_at_pa_output = tx_waveform_at_pa_output_pd;

%Do initial iteration
%Get initial memoryless pd coefficients
for n = 1:1:10
   %Get initial memoryless pd coefficients
   pd_coefficients = Memory_Polynomial_Solution(training_signal, tx_waveform_at_pa_output_pd / power(10, SYSTEM_POWER_GAIN_dB/20), DPD_POLYNOMIAL_ORDER, QPD);
   pd_tx_waveform = Memory_Polynomial_Amplifier(channel_1_baseband_waveform_relative*power(10, -PREDISTORTER_BACKOFF/20), pd_coefficients, DPD_POLYNOMIAL_ORDER, QPD);
   tx_waveform_at_pa_output_pd = Memory_Polynomial_Amplifier(pd_tx_waveform, pa_coefficients_with_memory, PA_POLYNOMIAL_ORDER, QPA);
   training_signal = pd_tx_waveform;
end

[filepath, name, ext] = fileparts(file);
nWrites = write_aeroflex_file( pd_tx_waveform, ['./ARB_FIles/' name '_pd.aiq'], false );

%Now receive the predistorted waveform
%receive
temp_1 = cconv(tx_waveform_at_pa_output_pd, filter_h);
temp_1 = temp_1(1+(ringing_length):1:end-(ringing_length));

%Downsample
temp_1_downsampled = downsample(temp_1(offset_1:end), baseband_oversampling_rate);

%Normalize Power for signal metrics
temp_1_normalized_downsampled = (mean(abs(Complex_Alphabet))).*temp_1_downsampled./mean(abs(temp_1_downsampled));;

[predistorted_pa_outout_decoded_complex_stream] = AWGN_maximum_likelyhood_decoder(temp_1_normalized_downsampled, Complex_Alphabet, Complex_Alphabet);

temp_1_normalized_downsampled = temp_1_normalized_downsampled(1:end-2);
predistorted_pa_outout_decoded_complex_stream = predistorted_pa_outout_decoded_complex_stream(1:end-2);
channel_2_symbols_normalized_relative = channel_2_symbols_normalized_relative(1:end-2);

SNR_dB_after_PA_with_PD = Measure_SNR(temp_1_normalized_downsampled, predistorted_pa_outout_decoded_complex_stream);
EVM_percent_after_PA_with_PD = 100*sqrt(1/power(10,SNR_dB_after_PA_with_PD/10));

tx_signal = channel_1_baseband_waveform_relative;

%plot
[gain_figure gain_axis] = create_gain_plot([], [], ...
                 10*log10(((abs(tx_signal)).^2)/(length(tx_signal)*50*0.001)), ...
                 10*log10(((abs(tx_waveform_at_pa_output)).^2)/(length(tx_waveform_at_pa_output)*50*0.001)) - 10*log10(((abs(tx_signal)).^2)/(length(tx_signal)*50*0.001)), ...
                 10*log10(((abs(tx_signal)).^2)/(length(tx_signal)*50*0.001)), ...
                 10*log10(((abs(tx_waveform_at_pa_output_pd)).^2)/(length(tx_waveform_at_pa_output_pd)*50*0.001)) - 10*log10(((abs(tx_signal)).^2)/(length(tx_signal)*50*0.001)), ...
                 [], ...
                 [], ...
                 -90, -50, -25, 35);

N_Averages = 20;
[psd_figure psd_axis] = create_psd_plot([], [], ...
                linspace(-1/2, 1/2, length(tx_signal)), ...
                20*log10(filtfilt(1./(N_Averages*ones(1,N_Averages)),1,abs(fftshift(fft(tx_signal, length(tx_signal)))))), ...
                linspace(-1/2, 1/2, length(tx_waveform_at_pa_output)), ...
                20*log10(filtfilt(1./(N_Averages*ones(1,N_Averages)),1,abs(fftshift(fft(tx_waveform_at_pa_output, length(tx_waveform_at_pa_output)))))), ...
                linspace(-1/2, 1/2, length(tx_waveform_at_pa_output_pd)), ...
                20*log10(filtfilt(1./(N_Averages*ones(1,N_Averages)),1,abs(fftshift(fft(tx_waveform_at_pa_output_pd, length(tx_waveform_at_pa_output_pd)))))), ...
                baseband_oversampling_rate, ...
                -40, ...
                30);

max_scale = max(abs(Complex_Alphabet));
[constellation_figure constellation_axis] = create_test_consteallation_plot([], [], ...
                           real(channel_1_symbols_normalized_relative), imag(channel_1_symbols_normalized_relative), ...
                           real(channel_2_symbols_normalized_relative), imag(channel_2_symbols_normalized_relative), ...
                           real(Complex_Alphabet), imag(Complex_Alphabet), ...
                           SNR_dB_before_PA, EVM_percent_before_PA, ...
                           SNR_dB_after_PA, EVM_percent_after_PA, ...
                           -1.5*max_scale, 1.5*max_scale, -1.5*max_scale, 1.5*max_scale);

[constellation_figure constellation_axis] = create_consteallation_plot([], [], ...
                           real(channel_2_symbols_normalized_relative), imag(channel_2_symbols_normalized_relative), ...
                           real(temp_1_normalized_downsampled), imag(temp_1_normalized_downsampled), ...
                           real(Complex_Alphabet), imag(Complex_Alphabet), ...
                           SNR_dB_after_PA, EVM_percent_after_PA, ...
                           SNR_dB_after_PA_with_PD, EVM_percent_after_PA_with_PD, ...
                           -1.5*max_scale, 1.5*max_scale, -1.5*max_scale, 1.5*max_scale);