{ config, lib }:
{
  colors = {
    # Core
    normal       = { fg = "white";        bg = "default"; };
    status       = { fg = "black";        bg = "green";   };
    indicator    = { fg = "black";        bg = "green";   };
    tree         = { fg = "green";        bg = "default"; };
    markers      = { fg = "red";          bg = "default"; };
    search       = { fg = "cyan";         bg = "default"; };
    quoted       = { fg = "green";        bg = "default"; };
    signature    = { fg = "brightblack";  bg = "default"; };
    hdrdefault   = { fg = "cyan";         bg = "default"; };
    tilde        = { fg = "brightblue";   bg = "default"; };

    # Index matchers
    indexNew     = { fg = "yellow";       bg = "default"; };  # ~N
    indexFlag    = { fg = "cyan";         bg = "default"; };  # ~F
    indexDel     = { fg = "red";          bg = "default"; };  # ~D
    indexToMe    = { fg = "green";        bg = "default"; };  # ~p
    indexFromMe  = { fg = "blue";         bg = "default"; };  # ~P

    # Per-column (NeoMutt)
    index_number  = { fg = "brightblack"; bg = "default"; };
    index_flags   = { fg = "yellow";      bg = "default"; };
    index_date    = { fg = "blue";        bg = "default"; };
    index_author  = { fg = "green";       bg = "default"; };
    index_size    = { fg = "brightblack"; bg = "default"; };  # muted
    index_subject = { fg = "white";       bg = "default"; };

    # Sidebar
    sidebar_ordinary  = { fg = "brightwhite"; bg = "default"; };
    sidebar_highlight = { fg = "black";       bg = "green";   };
    sidebar_divider   = { fg = "blue";        bg = "default"; };
    sidebar_flagged   = { fg = "magenta";     bg = "default"; };
    sidebar_new       = { fg = "yellow";      bg = "default"; };
  };
}
