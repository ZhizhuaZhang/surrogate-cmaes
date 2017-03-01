exp_id = 'exp_multiEC_01';
exp_description = 'Surrogate CMA-ES model using Multi-trained EC with sd2 criterion and GPs with single and double population, NOrigInit = 1, RankErrorThresh = 0.1; in 5D';

% BBOB/COCO framework settings

bbobParams = { ...
  'dimensions',         { 2, 5, 10 }, ...
  'functions',          num2cell(1:24), ...      % all functions: num2cell(1:24)
  'opt_function',       { @opt_s_cmaes }, ...
  'instances',          { [1:5 41:50] }, ...    % default is [1:5, 41:50]
  'maxfunevals',        { '250 * dim' }, ...
};

% Surrogate manager parameters

surrogateParams = { ...
  'evoControl',         { 'multitrained' }, ...    % 'none', 'individual', 'generation', 'doubletrained', 'multitrained'
  'modelType',          { 'gp' }, ...               % 'gp', 'rf', 'bbob'
  'evoControlPreSampleSize', { 0 }, ...             % {0.25, 0.5, 0.75}, will be multip. by lambda
  'evoControlTrainRange', { 10 }, ...               % will be multip. by sigma
  'evoControlTrainNArchivePoints', { '10*dim' },... % will be myeval()'ed, 'nRequired', 'nEvaluated', 'lambda', 'dim' can be used
  'evoControlSampleRange', { 1 }, ...               % will be multip. by sigma
  'evoControlNOrigInit', { 1 }, ...
  'evoControlRankErrorThresh', { 0.1 }, ...
  'evoControlRestrictedParam', { 0.1 }, ...
};

% Model parameters

modelParams = { ...
  'useShift',           { false }, ...
  'predictionType',     { 'sd2' }, ...
  'trainAlgorithm',     { 'fmincon' }, ...
  'covFcn',             { '{@covMaterniso, 5}' }, ...
  'hyp',                { struct('lik', log(0.01), 'cov', log([0.5; 2])) }, ...
  'nBestPoints',        { 0 }, ...
  'minLeaf',            { 2 }, ...
  'inputFraction',      { 1 }, ...
  'normalizeY',         { true }, ...
};

% CMA-ES parameters

cmaesParams = { ...
  'PopSize',            { '4 + floor(3*log(N))', '(8 + floor(6*log(N)))' }, ...        %, '(8 + floor(6*log(N)))'};
  'Restarts',           { 50 }, ...
};

logDir = '/storage/plzen1/home/bajeluk/public';
