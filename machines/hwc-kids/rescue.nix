{ lib..pkgs, ... }:
{
  users.mutableUsers = true;
  users.users.root.hashedPassword = lib.mkForce null;

