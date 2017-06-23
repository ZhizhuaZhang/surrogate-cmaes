function [fitness_raw, arx, arxvalid, arz, counteval, surrogateStats, lambda, origEvaled, newStopFlag, archive] = surrogateManager(cmaesState, inOpts, sampleOpts, counteval, flgresume, varargin)
% surrogateManager  controls sampling of new solutions and using a surrogate model
%
% @xmean, @sigma, @lambda, @BD, @diagD -- CMA-ES internal variables
% @countiter            the number of the current generation
% @fitfun_handle        handle to fitness function (CMA-ES uses string name of the function)
% @inOpts               options/settings for surrogate modelling
% @flgresume            resume run from a file
% @varargin             arguments for the fitness function (varargin from CMA-ES)
%
% returns:
% @surrogateStats       vector of numbers with variable model/surrogate statsitics
% @lambda               pop. size (can be changed during this run
% @origEvaled           binary vector with true values on indices of individuals which
%                       are evaluated by the original fitness

  persistent ec;
  % ec - one such instance for evolution control, persistent between
  % different calls of the surrogateManager() function

%   persistent archive;           % archive of original-evaluated individuals

  persistent observers;         % observers of EvolutionControls

  stopFlagHistoryLength = 3;    % history of CMA-ES restart suggestions
  persistent stopFlagHistory;   %
  persistent modelRMSEforRestart;       % RMSE threshold for suggesting the CMA-ES to restart

  % TODO: make an array with all the status variables from each generation

  % CMA-ES state variables
  xmean = cmaesState.xmean;
  lambda = cmaesState.lambda;
  countiter = cmaesState.countiter;

  % Defaults for surrogateOpts
  sDefaults.evoControl  = 'none';                 % none | individual | generation | doubletrained(restricted)
  sDefaults.evoControlPreSampleSize       = 0.2;  % 0..1
  sDefaults.evoControlIndividualExtension = 20;   % 1..inf (reasonable 10-100)
  sDefaults.evoControlSamplePreprocessing = false;
  sDefaults.evoControlBestFromExtension   = 0.2;  % 0..1
  sDefaults.evoControlTrainRange          = 8;    % 1..inf (reasonable 1--20)
  sDefaults.evoControlSampleRange         = 1;    % 1..inf (reasonable 1--20)
  sDefaults.evoControlOrigGenerations     = 1;    % 1..inf
  sDefaults.evoControlModelGenerations    = 1;    % 0..inf
  sDefaults.evoControlTrainNArchivePoints = '15*dim';
  sDefaults.evoControlValidatePoints      = 0;
  sDefaults.evoControlRestrictedParam     = 0.2;    % 0..1
  sDefaults.evoControlAdaptivity          = 0.1;
  sDefaults.evoControlSwitchMode          = []; % none | individual | generation | doubletrained(restricted)
  sDefaults.evoControlSwitchBound         = inf;    % 1 .. inf (reasonable 10--100)
  sDefaults.evoControlSwitchPopulation    = 1;      % 1 .. inf (reasonable 1--20)
  sDefaults.evoControlSwitchPopBound      = inf;    % 1 .. inf (reasonable 10--100)
  sDefaults.evoControlSwitchTime             = inf;
  sDefaults.modelType = '';                         % gp | rf
  sDefaults.modelOpts = [];                         % model specific options
  sDefaults.modelRMSEforRestart           = 5e-10;  % RMSE threshold for suggesting the CMA-ES to restart

  surrogateStats = [];
  origEvaled = false(1, lambda);
  newStopFlag = [];

  % copy the defaults settings...
  surrogateOpts = sDefaults;
  % and replace those set in the surrogateOpts:
  for fname = fieldnames(inOpts)'
    if (strcmp(fname, 'archive')), continue; end;
    surrogateOpts.(fname{1}) = inOpts.(fname{1});
  end

  assert(size(xmean,2) == 1, 'surrogateManager(): xmean is not a column vector!');
  dim = size(xmean,1);
  cmaesState.dim = dim;
  cmaesState.thisGenerationMaxevals = cmaesState.maxfunevals - counteval;

  % resume an interrupted EC
  if flgresume
    resumefilename = [inOpts.datapath filesep inOpts.exp_id '_eclog_' inOpts.expFileID '_' num2str(countiter-1) '.mat'];
    if ~exist(resumefilename, 'file')
      error('Recovery file ''%s'' not found.', resumefilename);
    end

    eclog = load(resumefilename);
    ec = eclog.ec;
    archive = ec.archive;
    % remove Inf's from the archive
    infY = find(isinf(archive.y));
    archive = archive.delete(infY);

    ec.observers = [];
    [ec, observers] = ObserverFactory.createObservers(ec, surrogateOpts);
    stopFlagHistory = false(1, stopFlagHistoryLength);
    modelRMSEforRestart = defopts(surrogateOpts, 'modelRMSEforRestart', sDefaults.modelRMSEforRestart);
  else
    archive = defopts(inOpts, 'archive', Archive(dim));
  end

  % switching evolution control
  % TODO: consider removing this completely
  if ~isempty(surrogateOpts.evoControlSwitchMode)
    surrogateOptsNew = surrogateOpts;
    surrogateOptsNew.evoControl = surrogateOpts.evoControlSwitchMode;
    % create new EC
    ec_new = ECFactory.createEC(surrogateOptsNew);
    % if the switch was not performed and it should be, do it
    if ~strcmp(class(ec_new), class(ec)) && ...
      (counteval > surrogateOpts.evoControlSwitchBound*dim || ...
      toc(surrogateOpts.startTime) > surrogateOpts.evoControlSwitchTime)
      fprintf('Switching evolution control from ''%s'' to ''%s''\n', ...
        surrogateOpts.evoControl, surrogateOpts.evoControlSwitchMode)
      surrogateOpts = surrogateOptsNew;
      % EC type has changed -> create new instance of EvolutionControl
      % TODO: delete the old instances of 'ec' and 'observers'
      ec = ec_new;
      [ec, observers] = ObserverFactory.createObservers(ec, surrogateOpts);
    end
  end

  % switching population size
  if ((sampleOpts.origPopSize == lambda) && (counteval >= surrogateOpts.evoControlSwitchPopBound*dim))
    lambda = ceil(surrogateOpts.evoControlSwitchPopulation * lambda);
    cmaesState.lambda = lambda;
  end

  % construct EvolutionControl and its Observers
  % Note: independent restarts of the whole CMA-ES still clears the archive
  if (countiter == 1 && (isempty(ec) || (counteval < ec.counteval)))
    % Restart outside CMA-ES just happend
    disp('==== Restart outside CMA-ES ====');
    ec = ECFactory.createEC(surrogateOpts);
    [ec, observers] = ObserverFactory.createObservers(ec, surrogateOpts);
    stopFlagHistory = false(1, stopFlagHistoryLength);
    modelRMSEforRestart = defopts(surrogateOpts, 'modelRMSEforRestart', sDefaults.modelRMSEforRestart);
  end

  % save the initial point to the archive if it was evaluated
  if (countiter == 1 && ~isnan(cmaesState.fxstart))
    archive = archive.save(xmean', cmaesState.fxstart, countiter);
  end

  if (countiter == 1 && (counteval >= 2))
    % Restart inside CMA-ES just happend
    disp('== Restart inside CMA-ES ==');
    % disable restart suggesting after the first restart
    modelRMSEforRestart = 0.0;
  end

  % save the initial point to the archive if it was evaluated
  if (countiter == 1 && ~isempty(cmaesState.fxstart))
    archive = archive.save(xmean', cmaesState.fxstart, countiter);
  end

  % run one generation according to evolution control
  [ec, fitness_raw, arx, arxvalid, arz, counteval, lambda, archive, surrogateStats, origEvaled] = ...
    ec.runGeneration(cmaesState, surrogateOpts, sampleOpts, archive, counteval, varargin{:});

  % STOPFLAGS -- update and check for new stopflag suggestions
  stopFlagHistory = circshift(stopFlagHistory, [0, 1]);
  % suggest restart if RMSE < 5e-10
  if (modelRMSEforRestart > 0 && isprop(ec, 'stats') ...
      && isfield(ec.stats, 'rmseReeval') ...
      && ~isempty(ec.stats.rmseReeval) && ec.stats.rmseReeval < surrogateOpts.modelRMSEforRestart)
    fprintf(2, 'S-CMA-ES is suggesting CMA-ES to restart due to low RMSE on re-evaled point(s).\n');
    stopFlagHistory(1) = true;
  else
    stopFlagHistory(1) = false;
  end
  % if the stopflag suggestion fired in 'stopFlagHistoryLength' consecutive generations,
  % tell CMA-ES to restart and reset the stopFlagHistory array
  if (all(stopFlagHistory))
    newStopFlag = 'stagnation';
    stopFlagHistory = false(1, stopFlagHistoryLength);
  end

  if (size(fitness_raw, 2) < lambda)
    % the model was in fact not trained
    % good EvolutionControl should not let come here!!!
    disp('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
    disp('EvolutionControl came back without full population of lambda points!');
    disp('It shouldn''t happen. Rest of points will be orig-evaluated.');
    disp('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
    [yNew, xNew, xNewValid, zNew, counteval] = sampleCmaes(cmaesState, sampleOpts, lambda - size(fitness_raw, 2), counteval, 'Archive', archive, varargin{:});
    archive = archive.save(xNewValid', yNew', countiter);

    % save the resulting re-evaluated population as the returning parameters
    fitness_raw = [fitness_raw yNew];
    arx = [arx xNew];
    arxvalid = [arxvalid xNewValid];
    arz = [arz zNew];
    origEvaled((end-length(yNew)+1):end) = true;
  end

  % Disable this assertion in BBComp production
  % assert(min(fitness_raw) >= min(archive.y), 'Assertion failed: minimal predicted fitness < min in archive by %e', min(archive.y) - min(fitness_raw));

  % check that the resulting points in arxvalid are inside bound
  % constraints
  inBounds = all(arxvalid == sampleOpts.xintobounds(...
      arxvalid, sampleOpts.lbounds, sampleOpts.ubounds));
  assert(all(inBounds), 'Assertion failed: arxvalid is out of bounds in generation %d', countiter);
end
