close all;
clear;
clc
addpath(genpath('./'));

%% Path planner
disp('Planning ...');
% This map is used to generate path and check collision
map_colli = load_map_inflated('maps/map1_full.txt', 0.5, 0.2, 0); % xy res, z res, margin
% This map is for visualization (without boundary obsatacles)
map = load_map('maps/map1.txt', 0.5, 0.15, 0.34); % 3 parameters are dummy

start = {[5.0 -1 3.5]};
stop  = {[5.0 19.0 .5]};

% # of quadrotors. In our case, it's always 1.
nquad = length(start);
for qn = 1:nquad
    tic
    path{qn} = dijkstra(map_colli, start{qn}, stop{qn}, true);
    toc
end

if nquad == 1
    figure(1);
    plot_path(map, path{1});
end
%% Spiral trajectory
a = 1;
c = .50;
t = linspace(0,10*pi,15);

y = a*sin(t);
z = a*cos(t);
x = t/(2*pi*c);

path = [x' y' z'];
path = [[-3 0 1];path;[13 0 1]];
figure(1)
plot3(path(:,1), path(:,2), path(:,3)); 
xlabel('x'); ylabel('y'); title('Circula helix');
axis equal
% pbaspect([1 1 1])
axis([-3 14 -1.5 1.5 -1.5 1.5])
grid on
%% Desired trajectory generation
% *Warning*
% Since demonstrated obstacles are dense, including narrow corridors, it 
% may take up to a minute to get collision free trajectory.
% It is highly recommended to use simpler map if you just need a
% demonstration.
[PATH, P, tau_vec] = desired_trajectory(map_colli, path);

%% ODE simulation
ts = [0 cumsum(tau_vec)];

% State: [x, v, pitch, roll, yaw, w]'
% Initial condition
x0 = [PATH(1,:) zeros(1,9)]';
% Disturbances on the initial condition
% x0(1:3) = x0(1:3)-[.1 .05 .15]';
% x0(4:6) = x0(4:6)+[.01 .01 .02]';
% Initial error of yaw angle must not exceed 90 degrees
% x0(7:9) = x0(7:9)+ones(3,1)*pi/18;
% x0(10:12) = x0(10:12) + .0;

% Model parameters
model_param.grav = 9.807;
model_param.mass = 1.477;
model_param.I = [0.01152 0 0;0 0.01152 0;0 0 0.0218];
model_param.arm_length = 0.263;
model_param.c_tf = 8.004e-4;
%%
% Gain
KK.Kp = 2500;%11.9;
KK.Kv = 750;%4.443;
KK.KR = 15000;%10;
KK.K_omega = 7300;%6;

% For real time video
target_fps = 2000;
t_sim = 0:1/target_fps:2;

% External force
start_T = 0;
duration = 0;   
mag = 0;
direction = [1 0 0]';
Fmat = extForce_gen(t_sim, start_T, duration, mag, direction);

% Run ode45
options =  odeset('RelTol',1e-1,'AbsTol',1e-1);
[tsave, xsave] = quad_sim(tau_vec, PATH, P, model_param, KK, t_sim, x0, Fmat, options);

%% Desired trajectory vs actual trajectory
desired_pos = zeros(length(tsave),3);
desired_vel = zeros(length(tsave),3);
desired_acc = zeros(length(tsave),3);
desired_jerk = zeros(length(tsave),3);
desired_yaw = zeros(length(tsave),1);
for i = 1:length(tsave)
    desired_s = desired_state(tau_vec, tsave(i), PATH, P);
    desired_pos(i,:) = desired_s.pos';
    desired_vel(i,:) = desired_s.vel';
    desired_acc(i,:) = desired_s.acc';
    desired_jerk(i,:) = desired_s.jerk';
    desired_yaw(i) = desired_s.yaw;
end
%%
figure(1)
% Desired trajectory
plot3(desired_pos(:,1),desired_pos(:,2),desired_pos(:,3))
hold on
grid on
axis equal
% Actual trajectory
plot3(xsave(:,1),xsave(:,2),xsave(:,3),'--')
hold off
% legend('Desired','Actual')
%%
figure(5)
subplot(4,1,1)
plot(tsave,xsave(:,7)*180/pi,'-b','LineWidth',1.0);title('Euler angles');ylabel('roll, \phi')
grid on
subplot(4,1,2)
plot(tsave,xsave(:,8)*180/pi,'-b','LineWidth',1.0);ylabel('pitch, \theta')
grid on
subplot(4,1,3)
plot(tsave,xsave(:,9)*180/pi,'-b','LineWidth',1.0);ylabel('yaw, \psi');%xlabel('time, sec')
grid on

%%
m = model_param.mass;
g = model_param.grav;
% pos error
ep = xsave(:,1:3)-desired_pos;
% vel error
ev = xsave(:,4:6)-desired_vel;
% accel error
calc_acc = diff(xsave(:,4:6))./diff(tsave);
% plot(tsave(1:end-1),calc_acc)
%
ea = calc_acc-desired_acc(1:end-1,:);
%%
% desired force
Fd = -KK.Kp.*ep -KK.Kv.*ev + m*desired_acc; 
Fd(:,3) = Fd(:,3) + m*g;
% Desired force derivative
% Fd_dot = -KK.Kp*ev -KK.Kv*ea + m*desired_jerk;
% desired rotation, Rd = [xbd ybd zbd]
zbd = zeros(length(tsave),3);
xcd = zeros(length(tsave),3);
zbdxcd = zeros(length(tsave),3);
norm_zbdxcd = zeros(length(tsave),1);
for i=1:length(tsave)
    zbd(i,:) = Fd(i,:)/norm(Fd(i,:));
    xcd(i,:) = [cos(desired_yaw(i)) sin(desired_yaw(i)) 0];
    dummy = hat_optr(zbd(i,:))*xcd(i,:)';
    zbdxcd(i,:) = dummy';
    norm_zbdxcd(i) = norm(zbdxcd(i,:));
end
figure(5)
subplot(4,1,4)
plot(tsave,norm_zbdxcd,'-','LineWidth',1.5)
grid on
%% Video generator
figure(1);
% plot_path(map, path{1});
filename = 'myVideo_helix_1000_6.avi';
video_gen(tsave, xsave, filename, 200, Fmat)
