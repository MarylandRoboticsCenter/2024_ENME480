##############
# modified full desktop image #
##############
FROM osrf/ros:humble-desktop-full AS mod_desktop_full

# Set default shell
SHELL ["/bin/bash", "-c"]

WORKDIR ${HOME}

# Basic setup
RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends --allow-unauthenticated \
    software-properties-common \
    build-essential \
    curl \
    g++ \
    git \
    ca-certificates \
    make \
    cmake \
    automake \
    autoconf \
    bash-completion \
    iproute2 \
    iputils-ping \
    libtool \
    pkg-config \
    libxext-dev \
    libx11-dev \
    mc \
    mesa-utils \
    nano \
    tmux \
    tzdata \
    xclip \
    x11proto-gl-dev && \
    sudo rm -rf /var/lib/apt/lists/*

# Set datetime and timezone correctly
RUN sudo ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo '$TZ' | sudo tee -a /etc/timezone

# Install ROS packages
RUN sudo apt-get update && sudo apt-get install -y \
    ros-dev-tools \
    python-is-python3 \
    python3-pip \
    python3-colcon-common-extensions python3-vcstool && \
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# RUN pip install -U $(pip list --outdated | grep colcon | awk '{printf $1" "}')

# upgrading colcon package to fix symlink issues
RUN pip3 install setuptools==58.2.0

# Install auxilary ROS packages
RUN sudo apt-get update && sudo apt-get install -y \
    ros-humble-gazebo-* \
    ros-humble-usb-cam \
    ros-humble-moveit-* && \
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*


#####################
# UR3e image #
#####################
FROM mod_desktop_full AS ur3e_dev

ARG WS_DIR="ament_ws"
ARG USERNAME=user
ARG userid=1000
ARG groupid=1020
ARG PW=user@123
ARG ROS_DOMAIN_ID=1
ARG YOUR_IP=127.0.0.1
ARG UR3E_IP=127.0.0.1


RUN groupadd -g ${groupid} -o ${USERNAME}
RUN useradd --system --create-home --home-dir /home/${USERNAME} --shell /bin/bash --uid ${userid} -g ${groupid} --groups sudo,video ${USERNAME} && \ 
    echo "${USERNAME}:${PW}" | chpasswd && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

ENV USER=${USERNAME} \
    LANG=en_US.UTF-8 \
    HOME=/home/${USERNAME} \
    XDG_RUNTIME_DIR=/run/user/${userid} \
    TZ=America/New_York

USER ${USERNAME}
WORKDIR ${HOME}

# custom Bash prompt
RUN { echo && echo "PS1='\[\e]0;\u \w\a\]\[\033[01;32m\]\u\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\] \\\$ '" ; } >> .bashrc

RUN sudo mkdir -p -m 0700 /run/user/${userid} && \
    sudo chown ${USERNAME}:${USERNAME} /run/user/${userid}

# Setup tmux config
ADD --chown=${USERNAME}:${USERNAME} https://raw.githubusercontent.com/MarylandRoboticsCenter/ENAE450/main/misc/.tmux.conf $HOME/.tmux.conf

# Install binary UR drivers (not from source)
RUN sudo apt-get update && sudo apt-get install -y \
    ros-humble-ur && \
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

# kept in case UR drivers should be installed from source
#     git clone -b humble https://github.com/UniversalRobots/Universal_Robots_ROS2_Driver.git src/Universal_Robots_ROS2_Driver && \
#     vcs import src --skip-existing --input src/Universal_Robots_ROS2_Driver/Universal_Robots_ROS2_Driver-not-released.${ROS_DISTRO}.repos && \
#     vcs import src --skip-existing --input src/Universal_Robots_ROS2_Driver/Universal_Robots_ROS2_Driver.${ROS_DISTRO}.repos && \

# Setup UR Drivers
RUN source /opt/ros/humble/setup.bash && \
    mkdir -p $HOME/ros_ur_driver/src && \
    cd ~/ros_ur_driver && \
    git clone -b humble https://github.com/UniversalRobots/Universal_Robots_ROS2_Gazebo_Simulation.git src/Universal_Robots_ROS2_Gazebo_Simulation && \
    sudo apt update -qq && \
    rosdep update && \
    rosdep install --ignore-src --from-paths src -y && \
    colcon build --symlink-install --executor sequential --cmake-args -DCMAKE_BUILD_TYPE=Release && \
    sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*

#####################
# UR3e MRC workspace #
#####################
FROM ur3e_dev AS ur3e_mrc_ws


# Set up UR3e workspace
RUN source /opt/ros/humble/setup.bash && \
	mkdir -p $HOME/${WS_DIR}/src && \
    cd $HOME/${WS_DIR} && \
	colcon build --symlink-install --executor sequential


# Set up working directory and bashrc
WORKDIR ${HOME}/${WS_DIR}/
RUN echo 'source /opt/ros/humble/setup.bash' >> $HOME/.bashrc && \
    echo 'source /usr/share/colcon_cd/function/colcon_cd.sh' >> $HOME/.bashrc && \
    echo 'source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash' >> $HOME/.bashrc && \
    echo >> $HOME/.bashrc && \
    echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}" >> $HOME/.bashrc && \
    echo 'export ROS_LOCALHOST_ONLY=1' >> $HOME/.bashrc && \
    echo >> $HOME/.bashrc && \
    echo "export YOUR_IP=${YOUR_IP}" >> $HOME/.bashrc && \    
    echo "export UR3E_IP=${UR3E_IP}" >> $HOME/.bashrc && \    
    echo >> $HOME/.bashrc && \    
    echo 'source $HOME/ros_ur_driver/install/setup.bash' >> $HOME/.bashrc && \    
    echo "source $HOME/${WS_DIR}/install/setup.bash" >> $HOME/.bashrc && \
    echo 'source /usr/share/gazebo/setup.bash' >> $HOME/.bashrc

WORKDIR ${HOME}
    
CMD /bin/bash
