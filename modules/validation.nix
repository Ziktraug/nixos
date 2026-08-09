{ config, lib, ... }:

{
  assertions = [
    {
      assertion = config.networking.hostName != "";
      message = "networking.hostName must be configured";
    }
  ];
}
