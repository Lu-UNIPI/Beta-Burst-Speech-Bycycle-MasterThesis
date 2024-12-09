close all;clear all;clc;
%%
PATH_DATA='Z:\DBS';

DATE=datestr(now,'yyyymmdd');
format long
% from previous analysis:
A=2; % median distance stim1 onset - syl 1 onset
B=1.26; % median distance syl1 onset - syl3 offset
IT=1.93; % median inter trial distance (syl3 offset - stim 1 onset)
LEFT=1.5;
RIGHT=1.5; 

% choose data to analyze
n_sub_PD_DBS=[3003,3006,3008,3010:3012,3014,3015,3018,3020:3022,3024,3025,3027,3028];
n_sub_PD_DBS=arrayfun(@(x) sprintf('%04d', x), n_sub_PD_DBS, 'UniformOutput', false);
SUBJECTS=n_sub_PD_DBS;

%% 
ii=1:numel(SUBJECTS);

for i=ii
    %open a subject dir
    if i==6;continue;end
    SUBJECT=strcat('DBS',string(SUBJECTS(i)));
    disp(strcat('Now running i= ',string(i),'   aka: ',SUBJECT))
    
    PATH_ANNOT=strcat(... 'Preprocessed data\Sync\annot');
    PATH_SIGNAL=strcat(... 'Preprocessed data\FieldTrip\');

    % take sessions with DBS LFP data
    session=bml_annot_read(strcat(PATH_ANNOT,filesep,SUBJECT,'_session'));
    id_session=session.id(strcmpi(session.type, 'LEAD'));

    % upload useful annot tables
    coding=bml_annot_read(strcat(...,'_coding')); coding=coding(coding.session_id==id_session,:);
    cue=bml_annot_read(strcat(...'_cue_precise')); cue=cue(cue.session_id==id_session, :);
    prod_triplet=bml_annot_read(strcat(...,'_produced_triplet'));prod_triplet=prod_triplet(prod_triplet.session_id==id_session,:);
    electrode=bml_annot_read(strcat(...,'_electrode'));
    electrode=electrode(:, {'id', 'starts','ends','duration','electrode','connector','port','HCPMMP1_label_1','HCPMMP1_weight_1'});
    
    load(fullfile(...+"_clean_syl.mat"));

    cfg=[];
    cfg.decodingtype='basic';   % 'basic', 'bysubject', 'weight'
                                % threshold_subj or threshold_weight
    electrode=bml_getEcogArea(cfg,electrode);

    tokeepCod=(~isnan(coding.syl1_onset));
    tokeepCue=(~isnan(cue.stim1_starts));
    switch string(SUBJECTS(i))
        case {'3003', '3010', '3015', '3020', '3025', '3027'};tokeepCue=tokeepCod;
        case {'3012','3014'};tokeepCod=tokeepCue;
        case {'3024'};tokeepCod=tokeepCod & tokeepCue;tokeepCue=tokeepCod;
        case {'3021'};idx=find(~tokeepCue)+1;idx=idx(1:2);tokeepCod(idx)=0;
    end
    center=coding.syl1_onset(tokeepCod);

    x=center - cue.stim1_starts(tokeepCue); %TRIAL SPECIFIC
    tf_baseline_t0=[-(x+0.9) -(x+0.1)];

    x=mean(coding.syl3_offset(tokeepCod) - center,'omitnan'); %MEDIATING
    tf_rebound_t0=[x+0.1 x+0.9];

    x_stim1=median(cue.stim1_starts(tokeepCue)-center,'omitnan');
    x_stim3_end=median(cue.stim3_ends(tokeepCue)-center,'omitnan');
    x_syl1=median(coding.syl1_onset(tokeepCod)-center,'omitnan');
    x_syl3_end=median(coding.syl3_offset(tokeepCod)-center,'omitnan');

    windows={'baseline','stimulus','prespeech','speech','rebound'};
    window_tags={'window60','window50','window40','window30','window20','window_onset'};
    timing_windows=struct();
    for w=1:numel(windows)
        window=windows{w};
        switch window
            case 'baseline'
                timing_windows.(window).start= mean(tf_baseline_t0(:,1),'omitnan');
                timing_windows.(window).end= mean(tf_baseline_t0(:,2),'omitnan');
            case 'stimulus'
                timing_windows.(window).start= x_stim1;
                timing_windows.(window).end= x_stim3_end;
            case 'prespeech'
                timing_windows.(window).start= x_stim3_end;
                timing_windows.(window).end= x_syl1;
            case 'speech'
                timing_windows.(window).start= x_syl1;
                timing_windows.(window).end= x_syl3_end;
            case 'rebound'
                timing_windows.(window).start= tf_rebound_t0(1);
                timing_windows.(window).end= tf_rebound_t0(2);
        end
    end

    tab_cycle=readtable(strcat('annot/general CTAR/',SUBJECT,'_cycle_bursts.txt'));
    % filter out bursts <=100ms 
    tab_cycle=tab_cycle(tab_cycle.duration>0.10001,:); 

    %% channels selection and referencing
    % ecog
    choice='ecog';
    switch choice
        case 'area'
            channels=electrode.HCPMMP1_area;
            channels=channels(~(cellfun('isempty',channels)));
            idx=find(cellfun(@(x) strcmp(x,'AAC'),channels));
            % "PMC","POC","IFC","SMC","TPOJ","LTC","DLPFC","IFOC","AAC","IPC"
            if sum(idx)==0
                warning('No channels in this area');
            else
                cfg=[];
                cfg.channel     =chan_selected;
                ECOG=ft_selectdata(cfg,E);
            end
        case 'ecog'
            cfg=[];
            cfg.channel     ={'ecog*'};
            ECOG=ft_selectdata(cfg,E);
    end
    cfg=[];
    cfg.label   = electrode.electrode;
    cfg.group   = electrode.connector;
    cfg.method  = 'CTAR';   % using trimmed average referencing
    cfg.percent = 50;       % percentage of 'extreme' channels in group to trim
    ECOG=bml_rereference(cfg,ECOG);
    % save(fullfile(PATH_SIGNAL,'LFP beta burst',SUBJECT+"_rebound_clean_ref_globt.mat"), 'E_ctar')
    

    % dbs
    cfg=[];
    cfg.channel     ={'dbs_L*'};
    DBS=ft_selectdata(cfg,E);
    if strcmp(SUBJECT,"DBS3028")
        cfg=[];
        cfg.channel=['all', strcat('-', {'dbs_LS','dbs_L10'})];
        DBS=ft_selectdata(cfg,DBS);
    end
    DBS=DBS_referencing(DBS);

    % unify set of data
    cfg=[];
    E=ft_appenddata(cfg,ECOG,DBS);

    chan_selected=E.label;
    electrode=electrode(ismember(electrode.electrode,ECOG.label),:);

    % remasking NaNs with zeros
    cfg=[];
    cfg.value           =0;
    cfg.remask_nan      =true;
    cfg.complete_trial  =true;
    E=bml_mask(cfg,E);

    %% burst probability BYCYCLE
    measures={'frequency','probability','duration','volt_amp','time_rdsym','time_ptsym'};%power
    tag='window50';
    annot_probability=table(); annot_duration=table(); annot_voltamp=table();
    annot_rdsym=table(); annot_ptsym=table(); annot_power=table();
    annot_frequency=table();
    annot_occurrence=table(); occ=1;

    %time = linspace(-(A+LEFT), B+RIGHT, 250 );
    time=linspace(timing_windows.baseline.start-0.05,timing_windows.rebound.end+0.05,60);
    electrodes_analysis= unique(tab_cycle.chan_id);
    for e=1:numel(electrodes_analysis)
        if startsWith(electrodes_analysis{e},'dbs_R');continue;end
        tab = tab_cycle( strcmp(tab_cycle.chan_id,electrodes_analysis(e)),:);
        trial_ids=unique(tab.trial_id);
        
        % select single channel 
        cfg=[];
        cfg.channel     ={electrodes_analysis{e}}; 
        Echannel=ft_selectdata(cfg,E);

        for m=1:numel(measures)
            disp(['-- analysis: ',measures{m}])


            xpos=nan(1,numel(windows));
            measure_windows=cell(1,numel(windows));
            for w=1:numel(windows)
                % mask the window
                start_window= timing_windows.(windows{w}).start;
                end_window= timing_windows.(windows{w}).end;
                [~,idx_start]=min(abs(time-start_window));
                [~,idx_end]=min(abs(time-end_window));
                window_time=time(idx_start:idx_end);
        
                % mask for each trial
                switch measures{m}
                    case 'probability'
                    measure_trials=nan(1,numel(trial_ids));
                    for j=1:numel(trial_ids)
                        subtab=tab( strcmp(tab.chan_id,electrodes_analysis(e)) & tab.trial_id==trial_ids(j)  & strcmp(tab.(tag),windows(w)),:);
                        mask=false(size(window_time));
                        try
                            for pp=1:height(subtab)
                                [~,idx_start]=min(abs(window_time-subtab.starts(pp)));
                                [~,idx_end]=min(abs(window_time-subtab.ends(pp)));
                                mask(idx_start:idx_end)=1;
                            end 
                        catch
                        end
                        measure_trials(j) = sum(mask) / length(mask);

                        % annot occurrence
                        warning off
                        annot_occurrence.id(occ)=occ;
                        annot_occurrence.label(occ)=electrodes_analysis(e);
                        annot_occurrence.trial_id(occ)=trial_ids(j);
                        annot_occurrence.window50(occ)=windows(w);
                        annot_occurrence.n_bursts(occ)=height(subtab);
                        annot_occurrence.perc_bursts(occ)= sum(mask) / length(mask);
                        warning on
                        occ=occ+1;
                    end


                    case {'duration','volt_amp','time_rdsym','time_ptsym','frequency'} 
                    measure_trials=cell(1,numel(trial_ids));
                    for j=1:numel(trial_ids)
                        subtab=tab( strcmp(tab.chan_id,electrodes_analysis(e)) & tab.trial_id==trial_ids(j)  & strcmp(tab.(tag),windows(w)),:);
                        m_trial=nan(1,height(subtab));
                        try
                            for pp=1:height(subtab)
                                m_trial(pp)=subtab.(measures{m})(pp);
                            end 
                        catch
                        end
                        if isempty(m_trial);measure_trials{j}=nan;
                        else;measure_trials{j}=m_trial;
                        end
                    end
                    measure_trials=cell2mat(measure_trials);


                    case 'voltage'
                    measure_trials=nan(1,numel(trial_ids));
                    for j=1:numel(trial_ids)
                        cfg=[];
                        cfg.trials=[1:numel(Echannel.trial)]==trial_ids(j);
                        Etrial=ft_selectdata(cfg,Echannel);
    
                        sig_trial=Etrial.trial{1}(Etrial.time{1}>start_window & Etrial.time{1}<end_window);
    
                        window_pxx=256;noverlap_pxx=128;nfft_pxx=512;fs_pxx=Etrial.fsample;
                        [pxx,freq_pxx]=pwelch(sig_trial,window_pxx,noverlap_pxx,nfft_pxx,fs_pxx);
                        idx_freq=freq_pxx>12 & freq_pxx<35;
                        measure_trials(j)=mean(pxx(idx_freq),'omitnan');
                    end

                end
                measure_windows{w}=measure_trials;
                
            end

            dataConcat = [];
            windowClass = [];
            for ii = 1:length(measure_windows)
                dataConcat = [dataConcat, measure_windows{ii}];
                windowClass = [windowClass, ii * ones(1, length(measure_windows{ii}))];
            end
            [p_value, tbl, stats] = anovan(dataConcat, {windowClass}, 'model', 'linear', 'varnames', {'Time window'},'display', 'off');
            F_value_all = tbl{2, 6};
            p_value_all=p_value;

            dataConcat = [];
            windowClass = [];
            trialClass = [];
            for ii = 3:length(measure_windows)
                dataConcat = [dataConcat, measure_windows{ii}];
                windowClass = [windowClass, ii*ones(1, length(measure_windows{ii}))];
            end
            [p_value, tbl] = anovan(dataConcat, {windowClass}, 'model', 'linear', 'varnames', {'Time windows'},'display', 'off');
            F_value_speech = tbl{2, 6};
            p_value_speech = p_value;
            

            % Post hoc t test analysis
            pv=nan(1,(numel(windows)-1));
            tstat=nan(1,(numel(windows)-1));
            for ii = 2:numel(windows)
                if sum(isnan(measure_windows{ii}))>0.8*length(isnan(measure_windows{ii}))
                    pv(ii-1)=nan;
                    tstat(ii-1)=nan;
                else
                    [~, p, ~, stats] = ttest2(measure_windows{ii},measure_windows{1});
                    pv(ii-1)=p;
                    tstat(ii-1)=stats.tstat;
                end
            end
            
            annot=table();
            annot.id=e;
            annot.label=electrodes_analysis(e);
            annot.fstat_all=F_value_all;
            annot.pv_all=p_value_all;
            annot.fstat_speech=F_value_speech;
            annot.pv_speech=p_value_speech;
            annot.ttest_t_stimulus= tstat(1);
            annot.ttest_pv_stimulus= pv(1);
            annot.ttest_t_prespeech= tstat(2);
            annot.ttest_pv_prespeech= pv(2);
            annot.ttest_t_speech= tstat(3);
            annot.ttest_pv_speech= pv(3);
            annot.ttest_t_rebound= tstat(4);
            annot.ttest_pv_rebound= pv(4);

            switch measures{m}
                case 'probability';annot_probability(e,:)=annot;
                case 'duration';annot_duration(e,:)=annot;
                case 'volt_amp';annot_voltamp(e,:)=annot;
                case 'time_rdsym';annot_rdsym(e,:)=annot;
                case 'time_ptsym';annot_ptsym(e,:)=annot;
                case 'power';annot_power(e,:)=annot;
                case 'frequency';annot_frequency(e,:)=annot;
            end
            
        end
    end
    if any(annot_frequency.id==0)
        annot_frequency=annot_frequency(~(annot_frequency.id==0),:); annot_frequency.id(:)=1:height(annot_frequency);
        annot_probability=annot_probability(~(annot_probability.id==0),:); annot_probability.id(:)=1:height(annot_probability);
        annot_duration=annot_duration(~(annot_duration.id==0),:); annot_duration.id(:)=1:height(annot_duration);
        annot_voltamp=annot_voltamp(~(annot_voltamp.id==0),:); annot_voltamp.id(:)=1:height(annot_voltamp);
        annot_rdsym=annot_rdsym(~(annot_rdsym.id==0),:); annot_rdsym.id(:)=1:height(annot_rdsym);
        annot_ptsym=annot_ptsym(~(annot_ptsym.id==0),:); annot_ptsym.id(:)=1:height(annot_ptsym);
        %annot_power=annot_power(~(annot_power.id==0),:); annot_power.id(:)=1:height(annot_power);
    end    

    writetable(annot_frequency, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_frequency.txt'), 'Delimiter', '\t');
    writetable(annot_probability, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_probability.txt'), 'Delimiter', '\t');
    writetable(annot_duration, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_duration.txt'), 'Delimiter', '\t');
    writetable(annot_voltamp, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_volt_amp.txt'), 'Delimiter', '\t');
    writetable(annot_rdsym, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_time_rdsym.txt'), 'Delimiter', '\t');
    writetable(annot_ptsym, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_time_ptsym.txt'), 'Delimiter', '\t');
    %writetable(annot_power, strcat('annot/general CTAR/anova1/',SUBJECT,'_anova1_power.txt'), 'Delimiter', '\t');

    writetable(annot_occurrence, strcat('annot/general CTAR/bursts occurrence/',SUBJECT,'_bursts_occurrence.txt'), 'Delimiter', '\t');
end
