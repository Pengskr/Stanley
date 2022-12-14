% 前轮反馈控制 Stanley法
clc
clear
close all
% load path_S.mat
% load path_Circle.mat
load path_Circle_clockwise.mat

%% 相关参数定义
RefPos = path;
targetSpeed = 10;           % 目标速度，单位： m /s
k = 5;                      % 增益参数
Kp = 0.8;                   % 速度P控制器系数
dt = 0.1;                   % 时间间隔，单位：s
L = 2.9;                    % 车辆轴距，单位：m

% 参考纯跟踪算法引入积分调节可以减小静态误差
Ki = 0.0;           % 积分调节系数
Err_integ = 0;

% 绘制参考轨迹
figure
plot(RefPos(:,1), RefPos(:,2), 'b', 'LineWidth', 2);
xlabel('纵向坐标 / m');
ylabel('横向坐标 / m');
grid on;
grid minor
axis equal
hold on 

% 计算轨迹的参考航向角-大地坐标系
diff_x = diff(RefPos(:,1)) ;
diff_x(end+1) = diff_x(end);
diff_y = diff(RefPos(:,2)) ;
diff_y(end+1) = diff_y(end);
RefHeading = atan2(diff_y ,diff_x);

%% 车辆初始状态
InitialState = [RefPos(1,:)+1, RefHeading(1)+0.02, 1];  % 纵向位置、横向位置、航向角、速度

% 将初始状态存入实际状态数组中
state = InitialState;
state_actual = state;
delta_actual = 0;

%% 主程序

% 循环遍历轨迹点
idx = 1;
latError_Stanley = [];
sizeOfRefPos = size(RefPos,1);
while idx < sizeOfRefPos-1 % 由于diff_x，diff_y计算方式的特殊性，不考虑最后一个参考点
    % 寻找距离前轮中心最近的点
    idx = findTargetIdx(state, RefPos);

    % 计算前轮转角
    [delta, latError] = stanley_control(idx,state,RefPos,RefHeading,k);

    % 前轮转角
    Err_integ = Err_integ + latError * dt;
    delta = delta + Ki * Err_integ;

    % 如果误差过大，退出循迹
    if abs(latError) > 3
        disp('误差过大，退出程序!\n')
        break
    end

    % 计算加速度
    a = Kp* (targetSpeed-state(4));
    
    % 更新状态量
    state_new = UpdateState(a,state,delta,dt,L);
    state = state_new;

    % 保存每一步的实际量
    state_actual(end+1,:) = state_new;
    delta_actual(end+1,:) = delta;
    latError_Stanley(end+1,:) =  [idx,latError];
end

%% 画图
% 跟踪轨迹
for i = 1:size(state_actual,1)
    % 实际位置
    scatter(state_actual(i,1), state_actual(i,2),150, 'r.');
    % 实际航向
    quiver(state_actual(i,1), state_actual(i,2), cos(state_actual(i,3)), sin(state_actual(i,3)),0.5, 'm', 'LineWidth', 1);     % 实际航向
    quiver(state_actual(i,1), state_actual(i,2), cos(state_actual(i,3)+delta_actual(i,:)), sin(state_actual(i,3)+delta_actual(i,:)),0.2, 'k', 'LineWidth', 1);
    pause(0.01)
end
legend('参考车辆轨迹', '实际行驶轨迹','实际航向')

% 横向误差
figure
subplot(1, 2, 1)
plot(latError_Stanley(:, 2));
grid on;
grid minor
title("横向误差")
ylabel('横向误差 / m');

% 前轮转角
subplot(1, 2, 2)
plot(delta_actual(:,1));
grid on; grid minor; title('前轮转角');

% 航向角
figure
subplot(1, 2, 1)
plot(RefHeading);
grid on; grid minor; title('参考航向角');
subplot(1, 2, 2)
plot(state_actual(:,3));
grid on; grid minor; title('实际航向角');

%  保存
path_stanley = state_actual(:,1:2);
save latError_Stanley.mat latError_Stanley

%% 子函数
function target_idx = findTargetIdx(state, RefPos)
    for i = 1:size(RefPos, 1)-1
        d(i, 1) = norm(state(1:2)-RefPos(i, :));
    end
    [~,target_idx] = min(d);  % 找到距离当前位置最近的一个参考轨迹点的序号
end

function [delta,latError] = stanley_control(idx,state,RefPos,RefHeading,k)
    % 根据百度Apolo，计算横向误差
    dx = RefPos(idx,1) -state(1);
    dy = RefPos(idx,2) -state(2);
    phi_r = RefHeading(idx);
%     latError = dy*cos(phi_r) - dx*sin(phi_r);
    latError = dy*cos(state(3)) - dx*sin(state(3));   % 应当使用实际航向角计算横向误差
    
    % 分别计算只考虑航向误差的theta和只考虑横向误差的theta
    theta_fai =  RefHeading(idx)- state(3);
    theta_y = atan2(k*latError,state(4));
    
    % 将两个角度合并即为前轮转角
    delta = theta_fai + theta_y;
    % 由于数值上计算的错位，可能导致转角的绝对值突然超过360°，因此作限制
    if abs(delta)>pi
        delta = (delta>0)*(delta-2*pi) + (delta<0)*(delta+2*pi);
    end
end

function state_new = UpdateState(a,state_old,delta,dt,L)
    state_new(1) =  state_old(1) + state_old(4)*cos(state_old(3))*dt; %纵向坐标
    state_new(2) =  state_old(2) + state_old(4)*sin(state_old(3))*dt; %横向坐标
    state_new(3) =  state_old(3) + state_old(4)*dt*tan(delta)/L;      %航向角
    % 物理上航向角的绝对值小于等于180，需要对数学上算出的航向角作修正使其具有物理意义
    if abs(state_new(3))>pi
        state_new(3) = (state_new(3)>0)*(state_new(3)-2*pi) + (state_new(3)<0)*(state_new(3)+2*pi);
    end 
    state_new(4) =  state_old(4) + a*dt;                              %纵向速度
end
