{
  prebuiltCmake = { fetchzip }: fetchzip {
    url = "https://cmake.org/files/v3.19/cmake-3.19.3-Linux-x86_64.tar.gz";
    hash = "sha256-r+bdir2TB110Vb8UqRxBoxbYkQIP0gsoSQwQRtphyu0=";
  };
  prebuiltGccBaremetal = { fetchzip }: fetchzip {
    url = "https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//1663142243961/Xuantie-900-gcc-elf-newlib-x86_64-V2.6.1-20220906.tar.gz";
    hash = "sha256-7uWcvYl4uySHCCOTThiEHSmlEBdZVRYW3cpqHztwUn4=";
  };
  prebuiltGccLinux = { fetchzip }: fetchzip {
    url = "https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//1663142514282/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.1-20220906.tar.gz";
    hash = "sha256-CwruscgjWk+pKd+OxSEoYjclzoazk6J2UaKufSmJz+0=";
  };
}
