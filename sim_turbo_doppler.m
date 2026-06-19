%+--------------------------------------------------------------------------------------------------+
% Frame structure : hfm--guard--FH chips--copy chips (N chips copied from the head of FH chips)
% 修改说明：时变Doppler匀加速，Monte Carlo多次仿真，Stage1 vs Stage2 BER对比
%+--------------------------------------------------------------------------------------------------+
clear;close all;clc
tic

%% 1-parameters setup
Fig_flag    = 1;
max_speed   = 15;
vc          = 1500;
max_dop     = max_speed / vc;
fs          = 48000;

%% 2-Modulation（固定调制参数，循环内不重复生成）
src_bit = importdata('dat56.mat');
load code_paras56
src_bit_scramble          = (src_bit ~= scramble_code56);
H_struct                  = H_struct_56_112_Gallager;
src_bit_scramble_ldpc     = encode_ldpc_mex(double(src_bit_scramble), H_struct);
src_bit_scramble_ldpc_itlv = src_bit_scramble_ldpc(itlv_seq112);

chip_n    = length(src_bit_scramble_ldpc_itlv);
chip_bits = src_bit_scramble_ldpc_itlv;
B         = 4000;
f0        = 10000;
load FH_paras112
chip_frq      = round(B / (HOPPING_N * HOPPING_m - 1));
ii            = 0 : HOPPING_N * HOPPING_m - 1;
chip_freq_seq = f0 + ii * chip_frq;
clear ii;
chip_dur = 1 / chip_frq;   % chip_len_exp=0

slots             = zeros(chip_n, 2);
slots(:,1)        = hop_pn112 * HOPPING_m;
slots(:,2)        = chip_bits';
hopping_chip_seq  = slots(:,1) + slots(:,2);
FH_chips          = FH_mod(fs, chip_dur, chip_n, chip_freq_seq, hopping_chip_seq);

T_HFM    = 0.05;
f1       = f0 + 200;
f2       = f0 + B - 200;
HFM_header = FM_mod(fs, T_HFM, f1, f2, 'HFM');

copy_size  = 16;
copy_chips = FH_chips(1 : copy_size * fs * chip_dur);
copy_len   = length(copy_chips);

zpad   = zeros(0.05 * fs, 1);
wav_FH = [HFM_header; zpad; FH_chips; copy_chips];

T_frame = chip_n * chip_dur;
FH_len  = length(FH_chips);
FH_total_len = ceil((chip_n + copy_size) * fs * chip_dur);
over_len     = max_dop * FH_total_len;

%% 3-Monte Carlo 参数
N_trial  = 30;       % 仿真次数（可改大，建议论文用100）
snr_list = -10 : 2 : -4;   % SNR扫描范围

% 时变Doppler参数
v0 = 5;   % 初始速度 m/s
a  = 3;   % 加速度 m/s²（加大以凸显时变效应）
V_func = @(t) v0 + a * t;
v_mid  = V_func(T_frame / 2);

fprintf('时变速度：v(t) = %.1f + %.1f*t m/s\n', v0, a);
fprintf('帧时长：%.3f s，帧中间速度：%.2f m/s\n\n', T_frame, v_mid);

%% 多径信道参数
ChannelNum      = 20;
delta_delay_mean= 1e-3;
Tguard          = 20e-3;
attenuation     = 20;

filter_l = 0.9 * min(chip_freq_seq);
filter_h = 1.1 * max(chip_freq_seq);

%% Stage 2 参数
M_win = 48;
R_in  = 100.0;
Q_in  = diag([1e-4, 1e-6]);
max_turbo_iter = 3;

%% 结果存储
ber_s1_all = nan(length(snr_list), N_trial);
ber_s2_all = nan(length(snr_list), N_trial);

for si = 1 : length(snr_list)
    snr = snr_list(si);
    fprintf('===== SNR = %d dB =====\n', snr);

    for trial = 1 : N_trial

        %% 信道模拟
        zero_pad      = zeros(fs*0.2 + unidrnd(fs*0.3), 1);
        signal_tx     = [zero_pad; wav_FH; zero_pad];

        signal_doppler = addDoppler_nonlinear(signal_tx, V_func, fs, length(signal_tx)/fs);

        hh = h_generate(fs, ChannelNum, delta_delay_mean, Tguard, attenuation);
        signal_mp = filter(hh, 1, signal_doppler);

        rcv_raw = add_noise(signal_mp, snr, fs, mean(chip_freq_seq), B);

        %% 接收预处理
        pband_signal = filter_denoise(rcv_raw, fs, filter_l, filter_h);

        %% 同步
        coarse_Syn = HFM_Syn(fs, pband_signal, HFM_header);
        if isempty(coarse_Syn) || coarse_Syn < 1
            continue;
        end
        offs_tmp = coarse_Syn + length(zpad);
        if (offs_tmp + FH_total_len + over_len) > length(pband_signal)
            continue;
        end

        %% Stage 1：全局Doppler估计
        seg_for_dop   = pband_signal(offs_tmp+1 : offs_tmp+FH_total_len+over_len);
        doppler_gamma = doppler_estimation(seg_for_dop, FH_len, copy_len, 0, max_dop);
        speed_estimate= (doppler_gamma - 1) * vc;

        if abs(doppler_gamma - 1) > max_dop
            doppler_gamma = 1;
            Syn_pos = coarse_Syn;
        else
            delta_T     = ((1 - doppler_gamma) * T_HFM * f2) / (doppler_gamma * (f1 - f2));
            delta_count = delta_T * fs * 0.8;
            Syn_pos     = coarse_Syn + delta_count;
        end

        offs       = round(Syn_pos + length(zpad) / doppler_gamma);
        chip_nn    = length(chip_bits);
        FH_len_dop = ceil(chip_nn * fs * chip_dur / doppler_gamma);

        if (offs < 1) || (offs + FH_len_dop > length(pband_signal))
            continue;
        end

        pband_FH        = pband_signal(offs : offs + FH_len_dop);
        Complex_pband_FH= hilbert(pband_FH);
        fkeep           = chip_freq_seq * doppler_gamma;
        chip_nsample_dop= (2 - doppler_gamma) * chip_dur * fs;

        %% Stage 1 解调 + LDPC
        bit_prob = zeros(1, chip_nn);
        g1 = 1;
        for kk = 1 : chip_nn
            lchip    = round(kk*chip_nsample_dop) - round((kk-1)*chip_nsample_dop);
            g2       = g1 + lchip - 1;
            si_idx   = hop_pn112(kk) * 2;
            chip_f   = fkeep([si_idx+1, si_idx+2]);
            chip_sig = Complex_pband_FH(g1:g2);
            bit_prob(kk) = chip_prob(chip_sig, lchip, fs, chip_f);
            g1 = g2 + 1;
        end

        dlv_seq = zeros(1, chip_nn);
        dlv_seq(itlv_seq112) = bit_prob;
        LLr_LDPC = LLr_2FSK(dlv_seq);
        [check_sum, dec_bits_LDPC, ~] = decode_ldpc_mex(LLr_LDPC, H_struct, 20);
        [~, ber_s1] = biterr(src_bit, ((dec_bits_LDPC') ~= scramble_code56));
        ber_s1_all(si, trial) = ber_s1;

        %% Stage 2：DA + Kalman + Turbo
        b_hat_codeword = encode_ldpc_mex(double(dec_bits_LDPC(:)), H_struct);
        b_hat_iter     = b_hat_codeword(itlv_seq112);

        ber_i = ber_s1;
        for iter = 1 : max_turbo_iter
            [win_signals, win_fbar, win_tcenter] = dehopping_phase_cont_v5(...
                Complex_pband_FH, fkeep, hop_pn112, b_hat_iter, ...
                chip_nsample_dop, fs, M_win, [0,0], 0);

            [dv_obs_i, ~] = sliding_fft_dv_v3_nogated(win_signals, win_fbar, fs, vc);

            [dv_sm_i, ~]  = kalman_smooth_dv(dv_obs_i, win_tcenter, Q_in, R_in);

            dg_i      = doppler_gamma + mean(dv_sm_i) / vc;
            fkeep_i   = chip_freq_seq * dg_i;
            chip_ns_i = (2 - dg_i) * chip_dur * fs;

            bit_prob_i = zeros(1, chip_nn);
            g1 = 1;
            for kk = 1:chip_nn
                lc = round(kk*chip_ns_i) - round((kk-1)*chip_ns_i);
                g2 = g1 + lc - 1;
                if g2 > length(Complex_pband_FH); break; end
                si_idx   = hop_pn112(kk)*2;
                chip_sig = Complex_pband_FH(g1:g2);
                bit_prob_i(kk) = chip_prob(chip_sig, lc, fs, fkeep_i([si_idx+1, si_idx+2]));
                g1 = g2 + 1;
            end

            dlv_i = zeros(1, chip_nn);
            dlv_i(itlv_seq112) = bit_prob_i;
            [cs_i, dec_i, ~] = decode_ldpc_mex(LLr_2FSK(dlv_i), H_struct, 20);
            [~, ber_i] = biterr(src_bit, ((dec_i') ~= scramble_code56));

            tmp_iter   = encode_ldpc_mex(double(dec_i(:)), H_struct);
            b_hat_iter = tmp_iter(itlv_seq112);

            if sum(cs_i) == 0; break; end
        end

        ber_s2_all(si, trial) = ber_i;

        if mod(trial, 10) == 0
            fprintf('  Trial %d/%d  BER_S1=%.4f  BER_S2=%.4f\n', ...
                trial, N_trial, ber_s1, ber_i);
        end
    end

    mean_s1 = mean(ber_s1_all(si,:), 'omitnan');
    mean_s2 = mean(ber_s2_all(si,:), 'omitnan');
    fprintf('  [SNR=%d] 平均 BER_Stage1=%.4f  BER_Stage2=%.4f\n\n', snr, mean_s1, mean_s2);
end

%% 绘图：BER vs SNR 曲线
mean_ber_s1 = mean(ber_s1_all, 2, 'omitnan');
mean_ber_s2 = mean(ber_s2_all, 2, 'omitnan');

if Fig_flag
    figure;
    semilogy(snr_list, mean_ber_s1, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', 'Stage1（全局恒定Doppler）'); hold on;
    semilogy(snr_list, mean_ber_s2, 'r-s', 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', 'Stage2（时变Turbo跟踪）');
    xlabel('SNR (dB)'); ylabel('BER');
    title(sprintf('BER vs SNR  [v(t)=%.0f+%.0ft m/s, %d次Monte Carlo]', v0, a, N_trial));
    legend('Location', 'southwest'); grid on;
    ylim([1e-4, 1]);
end

%% 单次详细展示（最后一次trial的结果）
if Fig_flag && exist('dv_sm_i','var') && exist('win_tcenter','var')
    v_true = V_func(win_tcenter);
    v_s1   = speed_estimate * ones(size(win_tcenter));
    v_s2   = speed_estimate + dv_sm_i;

    figure;
    plot(win_tcenter, v_true, 'k-',  'LineWidth', 2, 'DisplayName', '真实时变速度'); hold on;
    plot(win_tcenter, v_s1,   'b--', 'LineWidth', 1.5, 'DisplayName', 'Stage1恒定估计');
    plot(win_tcenter, v_s2,   'r-',  'LineWidth', 1.5, 'DisplayName', 'Stage2 Turbo跟踪');
    xlabel('时刻(s)'); ylabel('速度(m/s)');
    legend('Location', 'best'); grid on;
    title(sprintf('最后一次仿真速度估计对比 (SNR=%d dB)', snr));

    figure;
    plot(win_tcenter, dv_obs_i, 'b.', 'MarkerSize', 6, 'DisplayName', '残差观测'); hold on;
    plot(win_tcenter, dv_sm_i,  'r-', 'LineWidth', 2,  'DisplayName', 'Kalman平滑');
    xlabel('时刻(s)'); ylabel('速度残差(m/s)');
    legend('Location', 'best'); grid on;
    title('Stage2 速度残差跟踪');
end

toc

%% =========================================================================
%% 本地函数
%% =========================================================================

function [win_signals, win_fbar, win_tcenter] = dehopping_phase_cont_v5(...
    Complex_pband_FH, fkeep, hop_pn112, b_hat, chip_nsample_dop, fs, M, drift_params, mult_mode)
if nargin < 8 || isempty(drift_params), drift_params = [0,0]; end
if nargin < 9 || isempty(mult_mode),    mult_mode = 0; end
b0 = drift_params(1); b1 = drift_params(2);

chip_nn = length(b_hat);
N_win   = chip_nn - M + 1;
lchip_all     = zeros(1, chip_nn);
t_start       = zeros(1, chip_nn);
f_hop         = zeros(1, chip_nn);
grab_all      = zeros(1, chip_nn);
phi_model_acc = zeros(1, chip_nn);
grab1 = 1; t_elapsed = 0; running_phase = 0;
for kk = 1 : chip_nn
    lchip = round(kk*chip_nsample_dop) - round((kk-1)*chip_nsample_dop);
    lchip_all(kk) = lchip;
    t_start(kk)   = t_elapsed;
    grab_all(kk)  = grab1;
    slots_idx  = hop_pn112(kk)*2;
    f_hop_base = fkeep(slots_idx + 1 + b_hat(kk));
    if mult_mode
        f_hop(kk) = f_hop_base * (1 + b0 + b1*t_start(kk));
    else
        f_hop(kk) = f_hop_base + b0 + b1*t_start(kk);
    end
    phi_model_acc(kk) = running_phase;
    running_phase = running_phase + 2*pi*f_hop(kk)*lchip/fs;
    grab1     = grab1 + lchip;
    t_elapsed = t_elapsed + lchip/fs;
end

win_len_list = zeros(1, N_win);
for g = 1:N_win
    win_len_list(g) = sum(lchip_all(g:g+M-1));
end
win_len     = round(median(win_len_list));
win_signals = zeros(N_win, win_len);
win_fbar    = zeros(1, N_win);
win_tcenter = zeros(1, N_win);

for g = 1 : N_win
    seg = zeros(win_len, 1); ptr = 1;
    phi_ref = phi_model_acc(g);
    for kk = g : g+M-1
        lchip = lchip_all(kk);
        idx1  = grab_all(kk); idx2 = idx1 + lchip - 1;
        if idx2 > length(Complex_pband_FH), break; end
        chip_seg = Complex_pband_FH(idx1:idx2);
        n_vec    = (0:lchip-1)';
        y_k      = chip_seg .* exp(-1i*2*pi*f_hop(kk)*n_vec/fs);
        phi_corr = phi_model_acc(kk) - phi_ref;
        y_k_corr = y_k * exp(-1i*phi_corr);
        len_write= min(lchip, win_len-ptr+1);
        seg(ptr:ptr+len_write-1) = y_k_corr(1:len_write);
        ptr = ptr + lchip;
        if ptr > win_len, break; end
    end
    win_signals(g,:) = seg.';
    win_fbar(g)      = mean(f_hop(g:g+M-1));
    center_hop       = g + floor(M/2);
    win_tcenter(g)   = t_start(center_hop) + lchip_all(center_hop)/2/fs;
end
end

function [dv_obs, df_obs] = sliding_fft_dv_v3_nogated(win_signals, win_fbar, fs, vc)
% 无峰值门控版本，用MAD离群点剔除代替
if nargin < 4, vc = 1500; end
[N_win, win_len] = size(win_signals);
dv_obs   = zeros(1, N_win);
df_obs   = zeros(1, N_win);
search_bw= 80;

for g = 1 : N_win
    sig  = win_signals(g, :).';
    nfft = 2^nextpow2(win_len * 8);
    S    = fft(sig, nfft);
    f_ax = (0 : nfft-1) * fs / nfft;
    Sa   = abs(S);
    bw   = fs / nfft;

    idx_pos = find(f_ax > 0.5        & f_ax <= search_bw);
    idx_neg = find(f_ax >= fs-search_bw & f_ax <= fs-0.5);
    [pk_pos, ip]  = max(Sa(idx_pos));
    [pk_neg, in_] = max(Sa(idx_neg));

    if pk_neg >= pk_pos
        Sa_side  = Sa(idx_neg);   f_side = f_ax(idx_neg) - fs;   idx_peak = in_;
    else
        Sa_side  = Sa(idx_pos);   f_side = f_ax(idx_pos);         idx_peak = ip;
    end

    f_peak    = parab_peak_1D(Sa_side, idx_peak, f_side, bw);
    df_obs(g) = f_peak;
    dv_obs(g) = f_peak * vc / win_fbar(g);
end

% MAD离群点剔除后插值
dv_med = median(dv_obs);
dv_mad = median(abs(dv_obs - dv_med));
thr    = max(3 * dv_mad / 0.6745, 0.05);
bad    = abs(dv_obs - dv_med) > thr;
if any(bad) && sum(~bad) > 2
    x_good = find(~bad);
    dv_obs = interp1(x_good, dv_obs(~bad), 1:N_win, 'linear', 'extrap');
end
end

function fp = parab_peak_1D(Sa_seg, idx, f_ax_seg, bw)
n = length(Sa_seg);
if idx > 1 && idx < n
    y0 = Sa_seg(idx-1); y1 = Sa_seg(idx); y2 = Sa_seg(idx+1);
    d  = y0 - 2*y1 + y2;
    if abs(d) > eps
        delta = max(-0.5, min(0.5, 0.5*(y0-y2)/d));
    else
        delta = 0;
    end
    fp = f_ax_seg(idx) + delta * bw;
else
    fp = f_ax_seg(idx);
end
end
