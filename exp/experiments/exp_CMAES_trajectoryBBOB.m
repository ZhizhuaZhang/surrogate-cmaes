exp_id = 'exp_CMAES_trajectoryBBOB';
exp_description = 'Pure IPOP-CMA-ES for trajectory in the BBOB wrapper (f26)';

% BBOB/COCO framework settings

bbobParams = { ...
  'dimensions',         { 12 }, ...
  'functions',          { 26 }, ...           % all functions: num2cell(1:24)
  'opt_function',       { @opt_s_cmaes }, ...
  'instances',          { [1:5, 41:50] }, ...   % default is [1:5, 41:50]
  'maxfunevals',        { '30000' }, ...
  'resume',             { true }, ...
};

% Surrogate manager parameters

surrogateParams = { ...
  'evoControl',         { 'none' }, ...         % 'none', 'individual', 'generation', 'restricted'
  'observers',          { [] }, ...             % logging observers
};

modelParams = {};

% CMA-ES parameters

cmaesParams = { ...
  'PopSize',            { '(8+floor(6*log(N)))' }, ...        %, '(8 + floor(6*log(N)))'};
  'Restarts',           { 50 }, ...
  'DispModulo',         { 100 }, ...
};

logDir = '/storage/plzen1/home/bajeluk/public';
