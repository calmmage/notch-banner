"""Original repeat print for the velvet banner. Regenerate with Python + librsvg."""
import argparse
from math import cos, cosh, exp, pi, sin
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent / "Resources"
TAU = 2*pi

def line(points, width=3.3, opacity=.95, closed=False, dash=False):
    d = ' '.join(('M' if i == 0 else 'L') + f'{x:.2f},{y:.2f}' for i,(x,y) in enumerate(points))
    if closed: d += ' Z'
    stipple = ' stroke-dasharray="4 6"' if dash else ''
    return f'<path d="{d}" stroke="white" stroke-width="{width}" opacity="{opacity}" fill="none" stroke-linecap="round" stroke-linejoin="round"{stipple}/>'

def curve(fn,a=0,b=TAU,n=100,**style):
    return line([fn(a+(b-a)*i/n) for i in range(n+1)],**style)

def oval(x,y,rx,ry,**style):
    return curve(lambda t:(x+rx*cos(t),y+ry*sin(t)),**style)

def dot(x,y,r=3):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="white"/>'

def hand(x,y,s,size=35):
    return f'<text x="{x}" y="{y}" fill="white" font-family="Baskerville, serif" font-style="italic" font-size="{size}" text-anchor="middle">{s}</text>'

def arrow(x,y,X,Y,w=3):
    dx,dy=X-x,Y-y; mag=max(1,(dx*dx+dy*dy)**.5);dx/=mag;dy/=mag
    return line([(x,y),(X,Y)],w)+line([(X-12*dx+5*dy,Y-12*dy-5*dx),(X,Y),(X-12*dx-5*dy,Y-12*dy+5*dx)],w)

def cube():
    front=[(-44,-20),(19,-31),(24,31),(-39,44)]
    back=[(x+38,y-25) for x,y in front]
    return line(front,closed=True)+line(back[0:3])+''.join(line([a,b],2.6) for a,b in zip(front[:3],back[:3]))+line([front[3],back[3],back[0]],1.8,.65,dash=True)

def triangle():
    return line([(-70,43),(43,-46),(43,43)],closed=True)+line([(27,43),(27,28),(43,28)],2.4)+hand(-16,-11,'c',27)+hand(0,70,'a',27)

def bell():
    return line([(-75,38),(78,38)],2.1,.75)+curve(lambda x:(x,37-80*exp(-(x/32)**2/2)),-72,72)+line([(0,38),(0,-40)],1.9,.6,dash=True)+hand(49,-8,'σ',27)

def saddle():
    def xyz(x,y):return ((x-y)*42,(x+y)*16+(x*x-y*y)*21)
    return ''.join(curve(lambda t:xyz(k,t),-1,1,n=25,width=2.25) + curve(lambda t:xyz(t,k),-1,1,n=25,width=2.25) for k in (-1,-.6,-.2,.2,.6,1))

def cone():
    return oval(0,27,48,13)+line([(-48,27),(2,-52),(48,27)])+line([(2,-49),(0,27),(37,33)],1.9,.67,dash=True)+hand(16,-2,'h',25)

def rose():
    return curve(lambda t:(65*cos(3*t)*cos(t),-65*cos(3*t)*sin(t)),0,pi,n=200)+dot(0,0,2.5)

def riemann():
    f=lambda x:28-9*((x+65)/105)**2-50*((x+65)/135)**3
    stairs=[(-64,34)]
    for x in range(-64,55,17):
        stairs.extend([(x,f(x)),(x+17,f(x)),(x+17,34)])
    return line(stairs,2.2,.70)+curve(lambda x:(x,f(x)-3),-69,70)+line([(-72,35),(77,35)],2.5)+hand(48,63,'dx',24)

def golden():
    return line([(-66,-41),(66,-41),(66,41),(-66,41)],2.8,closed=True)+line([(16,-41),(16,41),(16,9),(66,9),(46,9),(46,41)],1.9,.72)+curve(lambda t:(20+3.5*exp(.27*t)*cos(t),8+3.5*exp(.27*t)*sin(t)),0,10.35,n=150)+hand(-42,68,'φ',29)

def torus():
    def point(u,v):
        ring=48+17*cos(v);return (ring*cos(u),.50*ring*sin(u)+15*sin(v))
    return ''.join(curve(lambda v:point(t,v),n=48,width=1.9,opacity=.80) for t in [-2.1,-1.55,-1,-.45,.2,.85,1.55,2.2,2.85])+curve(lambda t:point(t,0))+curve(lambda t:point(t,pi),width=2.3)

def unit():
    x,y=35,-33
    return oval(0,0,48,48)+line([(-66,0),(68,0)],1.9,.65)+line([(0,-62),(0,61)],1.9,.65)+line([(0,0),(x,y)])+dot(x,y)+curve(lambda t:(15*cos(t),-15*sin(t)),0,.75,n=12,width=2)+hand(67,-24,'θ',27)

def catenary():
    return curve(lambda x:(x,63-31*cosh(x/43)),-70,70)+dot(-70,-19)+dot(70,-19)+line([(-72,46),(78,46)],1.9,.6)+hand(9,76,'a cosh(x/a)',27)

def vectors():
    return arrow(-49,33,46,17)+arrow(-49,33,-13,-48)+arrow(-49,33,82,-62,2.6)+line([(-13,-48),(82,-62),(46,17)],2,.7,dash=True)+hand(-52,-9,'v',27)

def roots():
    pts=[(48*cos(i*TAU/5-.5*pi),48*sin(i*TAU/5-.5*pi)) for i in range(5)]
    return oval(0,0,48,48,width=2.2,opacity=.65)+line([pts[i] for i in (0,2,4,1,3)],width=2.6,closed=True)+''.join(dot(x,y) for x,y in pts)

def wave():
    return line([(-75,0),(79,0)],1.9,.65)+curve(lambda x:(x,-31*sin(x/19)),-74,74)+hand(46,53,'sin t',27)

def circle_theorem():
    a,b,c=(-52,0),(52,0),(20,-48)
    return oval(0,0,52,52,width=2.65)+line([a,b,c],closed=True,width=2.25)+''.join(dot(x,y,2.9) for x,y in [a,b,c])+dot(0,0,2.6)

def helix():
    return curve(lambda t:(t*9-66+9*cos(t),27*sin(t)) ,0,4.6*pi,n=200)+line([(-77,0),(85,0)],1.8,.55,dash=True)

def limacon():
    return curve(lambda t:((28+44*cos(t))*cos(t)-23,-(28+44*cos(t))*sin(t)),n=160)+hand(-44,53,'r(θ)',23)

def trefoil():
    return curve(lambda t:(21*(sin(t)+2*sin(2*t)),17*(cos(t)-2*cos(2*t))),0,TAU,n=170)

def matrix():
    return line([(-38,-42),(-50,-42),(-50,42),(-38,42)],2.8)+line([(38,-42),(50,-42),(50,42),(38,42)],2.8)+hand(-18,-9,'a',31)+hand(18,-9,'b',31)+hand(-18,27,'c',31)+hand(18,27,'d',31)

def spiral():
    return curve(lambda t:(6*exp(.19*t)*cos(t),-6*exp(.19*t)*sin(t)),0,4.2*pi,n=190)

def lorenz():
    def velocity(p):
        x,y,z=p
        return (10*(y-x), x*(28-z)-y, x*y-8*z/3)
    def offset(p,d,h):
        return tuple(a+h*b for a,b in zip(p,d))
    p=(.1,1.,20.)
    path=[]
    for i in range(7000):
        h=.006
        a=velocity(p)
        b=velocity(offset(p,a,h/2))
        c=velocity(offset(p,b,h/2))
        d=velocity(offset(p,c,h))
        p=tuple(v+h*(q+2*r+2*s+t)/6 for v,q,r,s,t in zip(p,a,b,c,d))
        if i>240 and i%2==0:
            path.append((p[0]*3.7, (27-p[2])*2.55))
    return line(path,0.85,.90)

def bifurcation():
    # High-resolution bifurcation diagram: 1,200 columns so even 8K / near-full curtains are razor-sharp.
    points=[]
    cols=1200
    for col in range(cols):
        rate=2.85+1.15*col/(cols-1)
        x=.193
        for i in range(460):
            x=rate*x*(1-x)
            if i>=370:
                points.append((col,round(105*(1-x),2)))
    d=' '.join(f'M{(a/(cols-1)*150-75):.2f},{b-52:.2f}h.12' for a,b in sorted(set(points)))
    return f'<path d="{d}" stroke="white" opacity=".92" stroke-width="0.48" stroke-linecap="round"/>'

def cycloid():
    return (curve(lambda t:(-63+20*(t-sin(t)),-33+20*(1-cos(t))),0,1.55*pi)
            +dot(-63,-33)+dot(-63+20*(1.55*pi-sin(1.55*pi)),-33+20*(1-cos(1.55*pi))))

def mobius():
    def project(t,v):
        r=44+v*cos(t/2)
        return (r*cos(t),.51*r*sin(t)+v*sin(t/2))
    return (curve(lambda t:project(t,13),0,2*TAU,n=180,width=2.8)
            +''.join(line([project(i*TAU/16,-13),project(i*TAU/16,13)],1.6,.8) for i in range(16)))

def koch():
    corners=[55*complex(cos(t),sin(t)) for t in [-pi/2,pi/6,5*pi/6]]
    path=corners+[corners[0]]
    for _ in range(2):
        expanded=[]
        for start,end in zip(path,path[1:]):
            step=(end-start)/3
            peak=start+step+step*complex(.5,-3**.5/2)
            expanded.extend([start,start+step,peak,start+2*step])
        path=expanded+[path[-1]]
    return line([(p.real,p.imag) for p in path],2.6)

def phase_orbits():
    # Hamiltonian level sets of a simple pendulum, H = v²/2 + 1 − cos(q).
    paths=[]
    for energy in [.25,.9,1.65,2.,2.6]:
        from math import acos, sqrt
        span=acos(1-energy) if energy<2 else pi
        for side in [-1,1]:
            paths.append(curve(lambda q:(q*22,side*sqrt(max(0,2*(energy-1+cos(q))))*17),
                               -span,span,n=90,width=1.8,opacity=.85))
    return ''.join(paths)

# An irregular stagger places hand-rotated motifs across the two-dimensional
# repeat. The last two lanes straddle the points of the swallowtail hem.
MOTIFS=[
 (116,88,-16,1.09,cube()), (351,77,15,.94,hand(0,9,'e<tspan dy="-16" font-size="22">iπ</tspan><tspan dy="16"> + 1 = 0</tspan>',39)),
 (598,85,-19,1.02,lorenz()), (847,91,18,1.02,cone()),
 (221,230,12,.98,catenary()), (457,209,-12,1.08,torus()), (689,230,14,.92,mobius()), (898,242,-19,1.02,phase_orbits()),
 (95,373,19,.95,koch()),(348,375,-18,1.0,riemann()),(586,353,11,.98,trefoil()),(801,381,17,1.02,cycloid()),
 (181,529,-21,1.09,saddle()),(417,520,11,.98,hand(0,9,'V − E + F = 2',30)),(650,522,-13,.98,golden()),(895,541,-10,.96,roots()),
 (96,684,-14,1.03,bifurcation()),(327,663,18,.98,vectors()),(570,683,-17,1.04,helix()),(790,676,12,1.05,circle_theorem()),
 (181,809,23,.89,limacon()),(493,801,13,1.04,hand(0,8,'∇ × ∇f = 0',38)),(869,808,-24,.91,spiral()),
]
def main():
    ap = argparse.ArgumentParser(description="Generate 8K mathematical atlases for NotchBanner.")
    ap.add_argument("--out", type=Path, default=ROOT)
    out = ap.parse_args().out
    out.mkdir(parents=True, exist_ok=True)
    ink=[]
    for x,y,angle,scale,shape in MOTIFS:
        ink.append(f'<g transform="translate({x} {y}) rotate({angle}) scale({scale})">{shape}</g>')
    for x,y,r in [(232,60,3),(505,116,2.6),(736,116,3.8),(64,226,3.4),(355,239,3),(797,275,3.7),(220,377,3),(704,385,2.8),(500,448,3.7),(66,516,2.6),(772,504,3),(267,579,2.8),(458,655,2.9),(911,706,3),(332,785,3.5),(724,776,2.7)]:
        ink.append(oval(x,y,r+1,r,width=1.9,opacity=.63))
    svg='<svg xmlns="http://www.w3.org/2000/svg" width="8192" height="8192" viewBox="0 0 1000 875" preserveAspectRatio="none">'+''.join(ink)+'</svg>'
    master=out/'banner-math.svg';master.write_text(svg+'\n')
    subprocess.run(['rsvg-convert',str(master),'-o',str(out/'banner-math.png')],check=True)
    master.unlink(missing_ok=True)
    plates=[
        (curve(lambda x:(x,66-29*cosh(x/46)),-72,72)+line([(-72,-6.2),(72,-6.2)],1,.65,dash=True)
         +dot(-72,-6.2,2)+dot(72,-6.2,2), 'y = a cosh(x / a)', 'Catenary'),
        (lorenz(), 'dx/dt = σ(y − x)', 'Lorenz attractor'),
        (bifurcation(), 'x<tspan dy="8" font-size="22">n+1</tspan><tspan dy="-8"> = r · x</tspan><tspan dy="8" font-size="22">n</tspan><tspan dy="-8">(1 − x</tspan><tspan dy="8" font-size="22">n</tspan><tspan dy="-8">)</tspan>', 'Period doubling'),
        (cycloid(), 'x = a(θ − sin θ)', 'Brachistochrone'),
    ]
    panels=[]
    for i,(drawing,equation,title) in enumerate(plates):
        x,y=250+(i%2)*500,250+(i//2)*500
        panels.append(f'<g transform="translate({x} {y})"><g transform="translate(0 -15) scale(2.25)">{drawing}</g>'
                      +hand(0,145,equation,34)+hand(0,-170,title,24)+'</g>')
    sheet='<svg xmlns="http://www.w3.org/2000/svg" width="8192" height="8192" viewBox="0 0 1000 1000">'+''.join(panels)+'</svg>'
    subprocess.run(['rsvg-convert','-o',str(out/'banner-plates.png')],input=sheet.encode(),check=True)
if __name__=='__main__':main()
