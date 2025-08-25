# shared/colors/deep-nord.nix - Global Deep Nord color scheme
# A darker, creamier version of Nord for better eye comfort

{
  colors = {
    # Base colors (Gruvbox Material inspired - much softer contrast)
    background = "#282828";      # Gruvbox material bg (warmer, softer than our dark blue)
    foreground = "#d4be98";      # Muted cream (less bright, easier on eyes)
    
    # Selection colors (softer)
    selection_bg = "#7daea3";    # Muted teal instead of bright cyan
    selection_fg = "#282828";
    
    # Cursor (softer)
    cursor = "#d4be98";
    cursor_text = "#282828";
    
    # URL/links (softer)
    url = "#7daea3";
    
    # Gruvbox Material inspired colors (much softer, muted)
    # Dark colors (normal) - desaturated for eye comfort
    color0  = "#32302F";  # softer black
    color1  = "#ea6962";  # muted red (less harsh than Nord)
    color2  = "#a9b665";  # muted green
    color3  = "#d8a657";  # warm muted yellow
    color4  = "#7daea3";  # soft teal-blue (instead of bright blue)
    color5  = "#d3869b";  # soft pink-purple
    color6  = "#89b482";  # muted aqua
    color7  = "#d4be98";  # soft cream (main foreground)
    
    # Bright colors - slightly brighter but still muted
    color8  = "#45403d";  # muted bright black  
    color9  = "#ea6962";  # same muted red
    color10 = "#a9b665";  # same muted green  
    color11 = "#d8a657";  # same muted yellow
    color12 = "#7daea3";  # same soft blue
    color13 = "#d3869b";  # same soft purple
    color14 = "#89b482";  # same muted aqua
    color15 = "#d4be98";  # same soft cream
    
    # Nord semantic colors for UI elements
    nord0  = "#1f2329";  # darkest (our custom background)
    nord1  = "#3b4252";  # dark
    nord2  = "#434c5e";  # medium dark
    nord3  = "#4c566a";  # medium
    nord4  = "#d8dee9";  # medium light
    nord5  = "#e5e9f0";  # light
    nord6  = "#f2f0e8";  # lightest (our custom foreground)
    nord7  = "#8fbcbb";  # frost cyan
    nord8  = "#88c0d0";  # frost blue
    nord9  = "#81a1c1";  # frost light blue
    nord10 = "#5e81ac";  # frost dark blue
    nord11 = "#bf616a";  # aurora red
    nord12 = "#d08770";  # aurora orange
    nord13 = "#ebcb8b";  # aurora yellow
    nord14 = "#a3be8c";  # aurora green
    nord15 = "#b48ead";  # aurora purple
    
    # Transparency values
    opacity_terminal = "0.95";
    opacity_inactive = "0.90";
    
    # CSS/Web colors (with # prefix for web use) - Gruvbox Material inspired
    css = {
      background = "#282828";
      foreground = "#d4be98";
      accent = "#7daea3";      # soft teal
      warning = "#d8a657";     # muted yellow
      error = "#ea6962";       # muted red
      success = "#a9b665";     # muted green
      info = "#7daea3";        # soft blue
    };
  };
}