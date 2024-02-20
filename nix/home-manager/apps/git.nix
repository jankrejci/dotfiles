{
    programs.git= {
        enable = true;
        delta.enable = true;
    		extraConfig.core.editor = "hx";
        aliases = {
            ll = "log --pretty=format:'%Cred%h% %Cgreen(%ad) %C(bold blue)<%<(18)%an>%Creset %s' --abbrev-commit --date=format:'%Y-%m-%d'";
        		ri = "rebase --interactive";
        		ria = "rebase --interactive --autosquash";
        		ra = "rebase --abort";
        		riam = "rebase --interactive --autosquash origin/master";
        		ram = "rebase --abort origin/master";
        		rc = "rebase --continue";
        		ap = "add -p";
        		cf = "commit --fixup";
        		cfh = "commit --fixup=HEAD";
        		c = "commit";
        		fm = "!git fetch; git checkout origin/master";
        		f = "fetch";
        		st = "status";
        		co = "checkout";
        		cob = "ceckout -b";
          
        };
    };
}
