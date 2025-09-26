{ lib, cfg }:
let
  userName     = let v = cfg.userName or "";     in if v != "" then v else "eric okeefe";
  primaryEmail = let v = cfg.primaryEmail or ""; in if v != "" then v else "eriqueo@proton.me";
  otherEmails  = let v = cfg.otherEmails or [];  in if v != [] then v else
                   [ "eric@iheartwoodcraft.com" "eriqueokeefe@gmail.com" "heartwoodcraftmt@gmail.com" ];
  newTags      = cfg.newTags or [ "unread" "inbox" ];
in { inherit userName primaryEmail otherEmails newTags; }
