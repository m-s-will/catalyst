# This Dockerfile creates a docker image for running paraview catalyst in containers
# at Elwetritsch TU KL. 
#
# The general expectation is that this container and ones layered on top of it
# will be run using Singularity with a cleaned environment and a contained
# file systems (e.g. singularity run -eC container.sif). The Singularity command
# is responsible for binding in the appropriate environment variables,
# directories, and files to make this work.

FROM ubuntu:18.04

SHELL ["/bin/bash", "-l", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y software-properties-common
RUN add-apt-repository ppa:fenics-packages/fenics;
RUN apt-get update && apt-get install -y git build-essential \
    libgl1-mesa-dev libxt-dev qt5-default libqt5x11extras5-dev \
    libqt5help5 qttools5-dev qtxmlpatterns5-dev-tools libqt5svg5-dev \
    python3-dev python3-numpy python3-pip libopenmpi-dev libssl-dev \
    libtbb-dev ninja-build wget dos2unix nano gfortran autoconf freeglut3-dev \
    curl libpthread-stubs0-dev unzip pkgconf libxcb-shm0-dev libxrandr-dev \
    libelf-dev flex bison mesa-utils wayland-protocols libwayland-egl-backend-dev \
    libpciaccess-dev llvm-10*  python-pybind11 \
    libboost-all-dev libeigen3-dev fenics libgmp3-dev libmpfr-dev
    



# We do most of our work in /home/docker for the same reason. This just
# sets up the base environment in which we can build more sophisticated
# containers
RUN mkdir /home/docker
RUN chmod 777 /home/docker
WORKDIR /home/docker
# Obtain workload app from GitHub
RUN git clone --recursive https://gitlab.kitware.com/paraview/paraview.git; cd paraview/; git checkout v5.8.0; git submodule update --init --recursive;



# install fenics and dependencies
RUN pip3 install vtk mpi4py matplotlib numpy ply pybind11 mako meson

RUN pip3 install fenics-ffc --upgrade
RUN PYBIND11_VERSION=2.2.3; wget -nc --quiet https://github.com/pybind/pybind11/archive/v${PYBIND11_VERSION}.tar.gz; \
    tar -xf v${PYBIND11_VERSION}.tar.gz && cd pybind11-${PYBIND11_VERSION}; \
    mkdir build && cd build && cmake -DPYBIND11_TEST=off .. && make install

RUN git clone https://github.com/FEniCS/fiat.git; \
    git clone https://bitbucket.org/fenics-project/dijitso; \
    git clone https://github.com/FEniCS/ufl.git; \
    git clone https://bitbucket.org/fenics-project/ffc; \
    git clone https://bitbucket.org/fenics-project/dolfin; \
    git clone https://bitbucket.org/fenics-project/mshr; \
    cd fiat    && pip3 install . && cd ..; \
    cd dijitso && pip3 install . && cd ..; \
    cd ufl     && pip3 install . && cd ..; \
    cd ffc     && pip3 install . && cd ..;

RUN mkdir dolfin/build && cd dolfin/build && cmake .. && make install && cd ../..; 
RUN mkdir mshr/build   && cd mshr/build   && cmake .. && make install && cd ../..; 
RUN cd dolfin/python && pip3 install . && cd ../..; 
RUN cd mshr/python   && pip3 install . && cd ../..

# replace log.py from ufl to be able to use pvpython, because vtkPythonStdStreamCaptureHelper has no attribute isatty
COPY log.py /usr/local/lib/python3.6/dist-packages/ufl/log.py

#install mesa
WORKDIR /usr/local
#RUN wget mesa.freedesktop.org/archive/older-versions/13.x/13.0.6/mesa-13.0.6.tar.gz && tar xvzf mesa-13.0.6.tar.gz && rm mesa-13.0.6.tar.gz

RUN wget https://dri.freedesktop.org/libdrm/libdrm-2.4.104.tar.xz && tar xvf libdrm-2.4.104.tar.xz && rm libdrm-2.4.104.tar.xz
RUN cd libdrm-2.4.104; mkdir build; cd build; meson ..; ninja; ninja install;

RUN wget mesa.freedesktop.org/archive/mesa-20.3.4.tar.xz && tar xvf mesa-20.3.4.tar.xz && rm mesa-20.3.4.tar.xz
WORKDIR /usr/local/mesa-20.3.4
RUN mkdir build; meson build/; meson configure build/ -Dosmesa=gallium -Dgallium-drivers=swrast,swr -Dglx=disabled -Degl=disabled; ninja -C build/; ninja -C build/ install;
# RUN autoreconf -fi
# RUN ./configure \
#     --enable-osmesa\
#     --disable-glx \
#     --disable-driglx-direct\ 
#     --disable-dri\ 
#     --disable-egl \
#     --with-gallium-drivers=swrast 

# RUN make -j 8; make install;


# build glu
ENV C_INCLUDE_PATH '/usr/local/mesa-20.3.4/include'
ENV CPLUS_INCLUDE_PATH '/usr/local/mesa-20.3.4/include'
WORKDIR /usr/local
RUN git clone http://anongit.freedesktop.org/git/mesa/glu.git

WORKDIR /usr/local/glu
RUN ./autogen.sh --enable-osmesa
RUN ./configure --enable-osmesa
RUN make -j 8
RUN make install
WORKDIR /home/docker


# install newer cmake version
RUN wget https://github.com/Kitware/CMake/releases/download/v3.18.1/cmake-3.18.1.tar.gz; mkdir build; cd build; tar xvfz ../cmake-3.18.1.tar.gz;
RUN cd build/cmake-3.18.1/; ./bootstrap; make; make install;

# Build paraview
RUN mkdir paraview_build; cd paraview_build; \
    cmake -G Ninja -DPARAVIEW_USE_VTKM=OFF \
    -DPARAVIEW_USE_QT=OFF \
    -DPARAVIEW_USE_PYTHON=ON \
    -DPARAVIEW_USE_MPI=ON \
    -DVTK_USE_X=OFF \
    -DVTK_OPENGL_HAS_OSMESA=ON \
    -DOSMESA_INCLUDE_DIR=/usr/local/mesa-20.3.4/include \
    -DOSMESA_LIBRARY=/usr/local/mesa-20.3.4/build/src/gallium/targets/osmesa/libOSMesa.so \
    -DPARAVIEW_BUILD_EDITION=CATALYST_RENDERING ../paraview; cmake --build .; cmake --install .;


# Build catalyst examples
COPY Catalyst /home/docker/paraview/Examples/Catalyst/
RUN cd paraview/Examples/Catalyst; mkdir build; cd build; \
    cmake -DCMAKE_PREFIX_PATH=/home/docker/paraview_build/ -DBUILD_EXAMPLES=ON ..; make;

EXPOSE 11111

# replace log.py from ufl to be able to use pvpython, because vtkPythonStdStreamCaptureHelper has no attribute isatty
COPY log.py /usr/lib/python3/dist-packages/ufl/log.py

# Copy workload script
COPY start_simulation.sh /home/docker/start_simulation.sh

RUN dos2unix /home/docker/start_simulation.sh
RUN chmod +x /home/docker/start_simulation.sh

#CMD ["/bin/bash"]
#ENTRYPOINT ["/home/docker/entrypoint.sh"]
ENTRYPOINT ["/home/docker/paraview_build/bin/pvserver"]
