function [ osp, p ] = osde( x, varargin )
%UNTITLED4 Summary of this function goes here
%   Detailed explanation goes here

if ~isempty(varargin) && ~isstruct(varargin{1})
    xe = varargin{1};
else
    xe = x;
end
if ~isempty(varargin) && isstruct(varargin{1})
    opts = varargin{1};
elseif length(varargin)>1
    opts = varargin{2};
else
    opts = struct;
end

p = [];
if iscell(x) % bulk mode, cv sigma2 on a subset if needed
    N = length(x);
    d = size(x{1},2);
    if ~isfield(opts,'inds')
        N_rot = get_opt(opts, 'N_rot', min(N,20));
        rprm = randperm(N,N_rot);
        norms = nan(N_rot,1);
        for ii=1:N_rot
            i = rprm(ii);
            param = osde(x{i}, opts);
            norms(ii) = sqrt(max(sum(param.inds.^2,2)));
        end
        max_norm = mean(norms);
        inds = outerprodinds(0:max_norm,d,max_norm);
        norms = sqrt(sum(inds.^2,2));
        [sv,si] = sort(norms);
        ind_used = si(sv<=max_norm);
        
        opts.inds = inds(ind_used,:);
        osp.inds = opts.inds;
    end
    % compute the projection coefficients
    pc = nan(N,size(inds,1));
    if ~isempty(xe)
        p = cell(N,1);
        for i=1:N
            [osp, p{i}] = osde(x{i}, xe, opts);
            pc(i,:) = osp.pc;
        end
    else
        for i=1:N
            osp = osde(x{i}, opts);
            pc(i,:) = osp.pc;
        end
    end
    osp.pc = pc;
else
    [n,d] = size(x);
    inds = get_opt(opts,'inds');
    cv = struct;
    if isempty(inds) % no indices for basis funcs given, CV
        % get all indices whose norm is less than some max value
        max_norm = get_opt(opts,'max_norm',18);
        inds = outerprodinds(0:max_norm,d,max_norm);
        norms = sqrt(sum(inds.^2,2));
        [sv,si] = sort(norms);
        ind_used = si(sv<=max_norm);
        norms = norms(ind_used);
        inds = inds(ind_used,:);
        cv.inds = inds;
        % evaluate the basis functions given by the indices
        %phix = evalbasis(x, inds+1);
        phix = eval_basis(x, inds);
        pc = mean(phix);
        % CV norm of indices with L2 score
        norm_vals = unique(norms);
        sumnorms2 = cumsum(pc.^2);
        sumphi2 = cumsum(sum( phix.^2 ));
        lastnorms = [norms(1:end-1)~=norms(2:end); true];
        scores = (1-2*n/(n-1))*sumnorms2(lastnorms) + (2/(n*(n-1)))*sumphi2(lastnorms);
        [~, tm] = min(scores);
        cv.lastnorms = lastnorms;
        cv.scores = scores;
        % get the norms less than the CVed value
        osp.inds = inds(norms<=norm_vals(tm),:);
        osp.pc = pc(norms<=norm_vals(tm))';
    else
        osp.inds = inds;
        osp.pc = mean(eval_basis(x, inds))';
    end
    osp.cv = cv;
    % evaluate estimated pdf
    if ~isempty(xe)
        %p = evalbasis(xe, osp.inds+1)*osp.pc;
        D = size(osp.inds,1);
        maxmem = get_opt(opts,'maxmem',2^30); % use no more than this to eval
        nstep = ceil(maxmem/(8*D));
        ne = size(xe,1);
        p = nan(ne,1);
        for ci = 1:ceil(ne/nstep)
            n1 = (ci-1)*nstep+1;
            n2 = min(ne,ci*nstep);
            p(n1:n2) = eval_basis(xe(n1:n2,:), osp.inds)*osp.pc;
        end
        %p = eval_basis(xe, osp.inds)*osp.pc;
        if get_opt(opts,'eps_trunc',true)
            %p(p<=eps) = min(p(p>eps));
            mp = min(p(p>eps));
            if ~isempty(mp)
                p(p<=eps) = mp;
            else
                p(p<=eps) = eps;
            end
        end
    end
    
end

end
