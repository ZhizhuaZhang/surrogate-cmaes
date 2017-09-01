classdef (Abstract) SplitGain
% SplitGain evaluates split functions used in decision trees using
% custom metric. The evaluation can be based on the data alone or on the
% output of a model. If the model is polynomial, optimized evaluation is
% used.
  
  properties %(Access = protected)
    X % input data
    y % output data
    minSize % min size of one side of the split
    modelFunc % function which creates new model
    weightedGain % whether gain is weighted by number of examples
    degree % degree of polynomial features
    XP % generated polynomial features
    allEqual % whether all y values are equal
    current % struct holding data for current node
    polyMethod % method for computing polynomial model - 'regress' or ''
  end
  
  methods
    function obj = SplitGain(options)
    % constructor
    % evaluates functions based on constant model
    %   (y, yPred, variancePred)
    % if 'degree' or 'modelFunc' is specified, uses custom model
    %   (y, yPred, variancePred)
    % if also 'probabilistic' is specified
    %   (y, yPred, variancePred, confidenceIntervalPred, probabilityPred)
    % options
    %   'minSize'       - specifies the min size of either side
    %   'degree'        - uses polynomial model of given degree
    %   'polyMethod'    - method for computing polynomial model
    %     ''            - defualt model
    %     'regress'     - regress function
    %   'modelFunc'     - uses custom model
    %   'weightedGain'  - whether gain is weighted by number of examples
      if nargin >= 1
        obj.minSize = defopts(options, 'minSize', 1);
        obj.degree = defopts(options, 'degree', []);
        obj.polyMethod = defopts(options, 'polyMethod', '');
        obj.modelFunc = defopts(options, 'modelFunc', []);
        obj.weightedGain = defopts(options, 'weightedGain', true);
      end
    end
    
    function obj = reset(obj, X, y)
    % resets the evaluator with new data (X, y)
      [n, ~] = size(X);
      obj.X = X;
      obj.y = y;
      obj.allEqual = size(obj.y, 1) == 0 ...
        || (size(obj.y, 2) == 1 && all(obj.y == obj.y(1, :)));
      if obj.allEqual
        return
      end
      if ~isempty(obj.degree)
        obj.XP = generateFeatures(X, obj.degree, true);
        obj.minSize = max(obj.minSize, size(obj.XP, 2));
      end
      obj.current = obj.getData(true(n, 1));
    end
    
    function gain = get(obj, splitter)
    % evaluates splitter function
      if obj.allEqual
        gain = -inf;
        return;
      end
      idx = splitter(obj.X);
      if sum(idx) < obj.minSize || sum(~idx) < obj.minSize
        gain = -inf;
        return;
      end
      left = obj.getData(idx);
      right = obj.getData(~idx);
      n = size(obj.y, 1);
      nLeft = size(left.y, 1);
      nRight = size(right.y, 1);
      if obj.weightedGain
        gain = obj.current.value ...
          - nLeft/n * left.value ...
          - nRight/n * right.value;
      else
        gain = obj.current.value - left.value - right.value;
      end
    end
  end
  
  methods (Abstract, Access = protected)
    value = getValue(obj, data)
    % evaluates data using custom metric
  end
  
  methods (Access = protected)
    function data = getData(obj, idx)
    % returns portion of data given by idx and stores its value
      data = struct;
      data.idx = idx;
      data.y = obj.y(idx, :);
      if size(data.y, 2) > 1
        % gradient model
      elseif isempty(obj.modelFunc) && isempty(obj.degree)
        % constant model
        mu = sum(data.y) / numel(data.y);
        r = data.y - mu;
        sd2 = r' * r / numel(r);
        data.yPred = repmat(mu, size(data.y));
        data.sd2 = repmat(sd2, size(data.y));
      elseif isempty(obj.modelFunc) && strcmpi(obj.polyMethod, 'regress')
        % polynomial model using regress
        XP = obj.XP(idx, :);
        warning('off', 'stats:regress:RankDefDesignMat');
        [~, ~, r, rint] = regress(data.y, XP);
        warning('on', 'stats:regress:RankDefDesignMat');
        data.yPred = data.y - r;
        ci = yPred + rint - r;
        data.sd2 = confidenceToVar(ci);
      elseif isempty(obj.modelFunc)
        % polynomial model
        XP = obj.XP(idx, :);
        warning('off', 'MATLAB:rankDeficientMatrix');
        warning('off', 'MATLAB:singularMatrix');
        warning('off', 'MATLAB:nearlySingularMatrix');
        data.yPred = XP * (XP \ data.y);
        % var(b) = E(b^2) * (X'*X)^-1
        r = data.y - data.yPred;
        mse = r' * r / numel(r);
        data.sd2 = mse * sum(XP / (XP' * XP) .* XP, 2);
        warning('on', 'MATLAB:rankDeficientMatrix');
        warning('on', 'MATLAB:singularMatrix');
        warning('on', 'MATLAB:nearlySingularMatrix');
      else
        % custom model
        X = obj.X(idx, :);
        model = obj.modelFunc();
        model = model.trainModel(X, data.y);
        [data.yPred, data.sd2] = ...
          model.modelPredict(X);
      end
      data.value = obj.getValue(data);
    end
  end
end