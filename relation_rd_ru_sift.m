function [ru,rd,rmse,cc] = relation_rd_ru_sift(pair_nr)
% compute the relation rd vs ru and the distortion center using SIFT
% correspondences in a image pair
% par_nr: number of image pair (from 1 to 22)
% ru: undistorted radius of correspondence points
% rd: distorted radius of correspondence points
% rmse: root-mean-square value of the retroprojected point errors
% cc: coordinates of the distortion center
%
load('points_gopro_sift');
ns = 50;  %number of selected correspondences
[pts1,pts2] = select_points(gopro(pair_nr),ns);
% image size
rows = 3000;
cols = 4000;
cc = 0.5*[cols; rows];  %initial value of distortion center
%
% initial parameters for rd vs ru relation
% ps contain the ordered values of s
ps = ones(2*ns,1);
pmin = 0.8*ones(2*ns,1);
pmax = ones(2*ns,1);
% A and b are used to apply the constrain s1 >= s2 >= ... >= sn
A = diag(ones(2*ns-1,1),1) - diag(ones(2*ns,1),0);
A(2*ns-1,:) = [];
b = zeros(2*ns-1,1);
% options for the objective functions to optimize the rd vs ru relation and
% distotion center
options = optimset('maxiter',3000,'maxfunevals',1e6,'display','off');
options_cc = optimset('display','off');
%
% find rd vs ru relation and distortion center using alternate optimization
for iter=1:10
    ps = fmincon(@minfun,ps,A,b,[],[],pmin,pmax,[],options,pts1,pts2,cc);
    cc = fminsearch(@minfuncc,cc,options_cc,pts1,pts2,ps);
    rmse = minfun(ps,pts1,pts2,cc);
    sum_areas = minfuncc(cc,pts1,pts2,ps);
    fprintf('iter = %d, rmse = %0.4f, sum_areas = %0.2f, cc = [%0.2f, %0.2f]\n',...
        iter,rmse,sum_areas,cc(1),cc(2));
end
rd = distorted_radius(pts1,pts2,cc);
% rearrange ps in the same order as rd
[rs,inds] = sort(rd);
ps(inds) = ps;
ru = rd./ps;
figure(1); plot(ru,rd,'bo'); grid on;
set(gca,'fontsize',12);
xlabel('$r_u$ (pixels)','Interpreter','Latex','fontsize',16);
ylabel('$r_d$ (pixels)','interpreter','latex','fontsize',16);

%=======================================================
% objective function to optimize rd vs ru
function res = minfun(ps,pts1,pts2,cc)
n = size(pts1,1);
% assign s1 and s2 to the first and second image point correspondences
% respectively, using the indices of the ordered values of rd
rd = distorted_radius(pts1,pts2,cc);
[rs,inds] = sort(rd);
p = zeros(2*n,1);
p(inds) = ps;
s1 = p(1:n);
s2 = p(n+1:2*n);
% subtract the distortion center from the point correspondence coordinates
ud1 = pts1(:,1) - cc(1);
vd1 = pts1(:,2) - cc(2);
ud2 = pts2(:,1) - cc(1);
vd2 = pts2(:,2) - cc(2);
% find the homography using the distorted point coordinates and the values
% of s1 and s2
M = [ud2 vd2 s2 zeros(n,3) -ud1.*ud2./s1 -ud1.*vd2./s1 -ud1.*s2./s1; ...
    zeros(n,3) ud2 vd2 s2 -vd1.*ud2./s1 -vd1.*vd2./s1 -vd1.*s2./s1];
[U,S,V] = svd(M);
H = reshape(V(:,9),3,3)';
% reproject the distorted points from the second to the first image
P = H * [ud2, vd2, s2]';
up = s1.*P(1,:)'./P(3,:)';
vp = s1.*P(2,:)'./P(3,:)';
res = sqrt(mean((up-ud1).^2 + (vp-vd1).^2));  %rmse value of reprojection errors

%==============================================================
% objective function to optimize the center of ditortion
function res = minfuncc(cc,pts1,pts2,ps)
% assign s1 and s2 to the first and second image point correspondences
% respectively, using the indices of the ordered values of rd
n = size(pts1,1);
p = zeros(2*n,1);
rd = distorted_radius(pts1,pts2,cc);
[rs,inds] = sort(rd);
p(inds) = ps;
s1 = p(1:n);
s2 = p(n+1:2*n);
% subtract the distortion center from the point correspondence coordinates
ud1 = pts1(:,1) - cc(1);
vd1 = pts1(:,2) - cc(2);
ud2 = pts2(:,1) - cc(1);
vd2 = pts2(:,2) - cc(2);
% find the homography using the distorted point coordinates and the values
% of s1 and s2
M = [ud2 vd2 s2 zeros(n,3) -ud1.*ud2./s1 -ud1.*vd2./s1 -ud1.*s2./s1; ...
    zeros(n,3) ud2 vd2 s2 -vd1.*ud2./s1 -vd1.*vd2./s1 -vd1.*s2./s1];
[U,S,V] = svd(M);
H = reshape(V(:,9),3,3)';
% reproject the distorted points from the second to the first image
P = H * [ud2, vd2, s2]';
up = s1.*P(1,:)'./P(3,:)';
vp = s1.*P(2,:)'./P(3,:)';
% the value of the objective function is the sum of areas of the triangles
% formed by the distorted points in the first image, the reprojected points
% from the second to the first images and the center of distortion (given
% that the coordinates were shifted, the center of distortion is now at the
% origin)
res = 0;
for i=1:n
    Q = [ud1(i) up(i) 0; vd1(i) vp(i) 0; 1 1 1];
    res = res + 0.5*abs(det(Q));
end

%========================================================================
% join the distorted radius of the points in the first and second images
function rd = distorted_radius(pts1,pts2,cc)
rd1 = sqrt((pts1(:,1)-cc(1)).^2 + (pts1(:,2)-cc(2)).^2);
rd2 = sqrt((pts2(:,1)-cc(1)).^2 + (pts2(:,2)-cc(2)).^2);
rd = [rd1; rd2];

%===========================================================
% select ns SIFT correpondences
function [psel1,psel2] = select_points(gopro,ns)
% differences in the coordinates of the second and first image
% correspondences
d = gopro.pts2 - gopro.pts1;
dm = median(d);
r = sqrt((d(:,1)-dm(:,1)).^2 + (d(:,2)-dm(:,2)).^2);
rs = sort(r);
% select the ns points with less deviation from the median of the
% coordinate differences
ind = find(r<=rs(ns));
ind = ind(1:ns);
psel1 = gopro.pts1(ind,:);
psel2 = gopro.pts2(ind,:);