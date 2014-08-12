function [ active, supp, lambda, lambdae, lambdar, lambdas, lambdaes, lambdars ] = ...
    cv_supp_FuSSO( Y, PC, p, varargin )
%cv_supp_FuSSO Summary of this function goes here
%   Detailed explanation goes here
if isempty(varargin)
    opts = struct;
else
    opts = varargin{1};
end
N = size(PC,1);
M_n = size(PC,2)/p;
verbose = get_opt(opts,'verbose',false);
% get lambdas
intercept = get_opt(opts,'intercept',true);
lambdas = get_opt(opts,'lambdas',[]);
if isempty(lambdas)
    nlambdas = get_opt(opts,'nlambdas',100);
    min_lambda_ratio = get_opt(opts,'min_lambda_ratio',1E-2);
    if intercept
        Y_0 = Y-mean(Y);
    else
        Y_0 = Y;
    end
    max_lambda = max(sqrt(sum(reshape(PC'*Y_0,M_n,[]).^2,1)));
    b = max_lambda*min_lambda_ratio;
    B = max_lambda;
    lambdas = b*((B/b).^([(nlambdas-1):-1:0]/(nlambdas-1)));
else
    nlambdas = length(lambdas);
end
maxactive = get_opt(opts,'maxactive',inf);
lambdars = get_opt(opts,'lambdars',10.^(15:-1:-15));
nlambdars = length(lambdars);
lambdaes = get_opt(opts,'lambdaes',[0 4.^(1:2)]);
nlambdaes = length(lambdaes);
% get training/hold-out sets
trn_set = get_opt(opts,'trn_set',[]);
if isempty(trn_set)
    trn_perc = get_opt(opts,'trn_perc',.9);
    trn_set = false(N,1);
    trn_set(randperm(N,ceil(N*trn_perc))) = true;
end
N_trn = sum(trn_set);
N_hol = sum(~trn_set);
PC_hol = PC(~trn_set,:);
Y_hol = Y(~trn_set);
PC = PC(trn_set,:);
Y = Y(trn_set);

% set opti params
cv_opts = struct;
cv_opts.maxIter = 50000;
cv_opts.epsilon = 1E-10;
cv_opts.accel = true;
cv_opts.verbose = false;

funcs = make_active_group_lasso_funcs();
screen = inf(p,1);
strong_lambdas = inf(p,1);
params.K = PC;
params.Y = Y;
params.gsize = M_n;
params.lambda1 = 0;
params.intercept = intercept;

best_hol_MSE = inf;
best_active = [];
best_supp = [];
best_lambda = nan;
best_lambdar = nan;
best_lambdae = nan;
stime = tic;
for le = 1:nlambdaes
    params.lambdae = lambdaes(le);
    tt_a = zeros(size(PC,2)+intercept,1);
    for l = 1:nlambdas
        params.lambda2 = lambdas(l);

        [tt_a,screen,strong_lambdas] = fista_active(tt_a, funcs, lambdas(max(l-1,1)), lambdas(l), strong_lambdas, screen, params, cv_opts);
        if intercept
            tt_norms = sqrt(sum(reshape(tt_a(1:end-1),M_n,[]).^2,1));
        else
            tt_norms = sqrt(sum(reshape(tt_a,M_n,[]).^2,1));
        end
        gactive = tt_norms>0;
        nactive = sum(gactive);
        active = repmat(gactive,M_n,1);
        active = active(:);

        % get ridge estimates using found support -- fast for fat matrices
        best_hol_MSE_r = inf;
        best_lambdar_r = nan;
        if nactive>0
            if intercept
                PC_act = [PC(:,active) ones(N_trn,1)];
                PC_hol_act = [PC_hol(:,active) ones(N_hol,1)];
            else
                PC_act = PC(:,active);
                PC_hol_act = PC_hol(:,active);
            end
            [U,S] = eig(PC_act*PC_act');
            S = diag(S);
            PCtU = PC_act'*U;
            PCtY = PC_act'*Y;
            UtPCPCtY = PCtU'*PCtY;
            hol_MSEs = nan(nlambdars,1);
            for lr=1:nlambdars
                lambdar = lambdars(lr);
                %beta_act = (1/lambdar)*(Ig-PC_act'*U*diag(1./(S+lambdar))*U'*PC_act)*(PC_act'*Y);
                beta_act = (1/lambdar)*(PCtY-PCtU*(UtPCPCtY./(S+lambdar)));
                hol_MSE = mean( (Y_hol-PC_hol_act*beta_act).^2 );
                hol_MSEs(lr) = hol_MSE;
                if hol_MSE<best_hol_MSE_r
                    best_hol_MSE_r = hol_MSE;
                    best_lambdar_r = lambdars(lr);
                end
                if hol_MSE<best_hol_MSE
                    best_hol_MSE = hol_MSE;
                    best_active = gactive;
                    best_supp = active;
                    best_lambda = lambdas(l);
                    best_lambdar = lambdars(lr);
                    best_lambdae = lambdaes(le);
                end
            end
        else
            if intercept
                best_hol_MSE_r = mean((Y_hol-tt_a(end)).^2);
            else
                best_hol_MSE_r = mean(Y_hol.^2);
            end
            if best_hol_MSE_r<best_hol_MSE
                best_hol_MSE = best_hol_MSE_r;
                best_active = gactive;
                best_supp = active;
                best_lambda = lambdas(l);
                best_lambdar = nan;
                best_lambdae = lambdaes(le);
            end
        end
        
        if verbose
            fprintf('[l:%g, lr:%g, le:%g] active: %i, hol_mse: %g elapsed:%f \n', lambdas(l), best_lambdar_r, lambdaes(le), nactive, best_hol_MSE_r, toc(stime));
        end

        if nactive>maxactive
            break;
        end
    end
end
active = best_active;
supp = best_supp;
lambda = best_lambda;
lambdar = best_lambdar;
lambdae = best_lambdae;

end

