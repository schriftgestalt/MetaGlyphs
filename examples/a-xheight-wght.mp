alpha := 0.65;
beta := 0.24;

% Weight controls the pen's wide diameter; u scales with the UPM.
numeric nibwidth;
nibwidth := wght*u;

% Points use the layer width and x-height.
x1 = 0;       y1 = 0.8*xheight;
x4 = w;       y4 = 0.2*xheight;
y2 = xheight; y3 = 0;
x2 = (alpha-beta)*w;
x5 = alpha*w;
x3 = (alpha+beta)*w;
y5 = 0.5*xheight;
x6 = 0;       y6 = 0.3*xheight;
x7 = 0.2*w;   y7 = 0;
x8 = x5;      y8 = 0.2*xheight;

pickup pencircle
  xscaled nibwidth
  yscaled (0.2*nibwidth)
  rotated 30;

draw z1{dir 30}..z2{right}..z5{down}..z3{right}..z4{dir 30};
draw z5..z6{down}..z7{right}..z8;
