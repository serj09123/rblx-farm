"""Procedural low-poly Puffpaw (Skyheart Ranch, Common) -> GLB + OBJ with palette texture."""
import sys, numpy as np, trimesh
from PIL import Image

OUT = sys.argv[1]
rng = np.random.default_rng(7)

# palette texture: 8 swatches in a row, 16px each
PAL = {
    "fur": (245, 240, 255), "fur2": (228, 220, 248), "pink": (255, 182, 193),
    "pink2": (255, 140, 170), "eye": (30, 24, 48), "white": (255, 255, 255),
    "nose": (235, 110, 150), "blush": (255, 160, 185),
}
names = list(PAL)
img = Image.new("RGB", (16 * len(names), 16))
for i, n in enumerate(names):
    img.paste(PAL[n], (i * 16, 0, i * 16 + 16, 16))
img.save(f"{OUT}/puffpaw_palette.png")

def uv_for(name, n):
    i = names.index(name)
    return np.tile([(i * 16 + 8) / img.width, 0.5], (n, 1))

parts = []
def add(mesh, color):
    mesh.visual = trimesh.visual.TextureVisuals(uv=uv_for(color, len(mesh.vertices)))
    parts.append(mesh)

def sphere(r, center, sub=2, scale=(1, 1, 1)):
    m = trimesh.creation.icosphere(subdivisions=sub, radius=r)
    m.vertices *= scale
    m.vertices += center
    return m

# body: fluffy squashed ball (Y up). Fur tufts via low-freq displacement.
body = trimesh.creation.icosphere(subdivisions=3, radius=1.0)
v = body.vertices
d = np.sin(v[:, 0] * 7) * np.sin(v[:, 1] * 6 + 1) * np.sin(v[:, 2] * 7 + 2)
body.vertices = v * (1 + 0.045 * d + rng.normal(0, 0.006, len(v)))[:, None]
body.vertices *= (1.0, 0.92, 0.95)
add(body, "fur")

# belly patch (slightly lighter tone, front = +Z)
add(sphere(0.62, (0, -0.22, 0.42), 2, (1, 0.85, 0.6)), "fur2")

# ears: rounded teardrop ellipsoids with pink inner
for s in (-1, 1):
    R = trimesh.transformations.rotation_matrix(s * -0.4, (0, 0, 1))
    ear = sphere(0.22, (0, 0, 0), 2, (1, 1.6, 0.6)); ear.apply_transform(R)
    ear.apply_translation((s * 0.45, 0.78, -0.05)); add(ear, "fur")
    inner = sphere(0.13, (0, 0, 0), 2, (1, 1.5, 0.4)); inner.apply_transform(R)
    inner.apply_translation((s * 0.46, 0.8, 0.05)); add(inner, "pink")

# eyes: big dark ovals + highlights
for s in (-1, 1):
    add(sphere(0.17, (s * 0.33, 0.12, 0.87), 2, (0.9, 1.15, 0.5)), "eye")
    add(sphere(0.055, (s * 0.33 + 0.05, 0.2, 0.96), 1), "white")
    add(sphere(0.025, (s * 0.33 - 0.04, 0.07, 0.97), 1), "white")
    # blush
    add(sphere(0.11, (s * 0.55, -0.08, 0.77), 1, (1, 0.6, 0.35)), "blush")

# nose
add(sphere(0.06, (0, -0.02, 0.98), 1, (1.3, 0.8, 0.7)), "nose")

# paws (4 little pink beans)
for x, z in ((-0.42, 0.45), (0.42, 0.45), (-0.45, -0.35), (0.45, -0.35)):
    add(sphere(0.2, (x, -0.86, z), 2, (1, 0.6, 1.1)), "pink2")

# tail puff
add(sphere(0.2, (0, -0.25, -0.93), 2), "fur2")

mesh = trimesh.util.concatenate(parts)
tex = trimesh.visual.TextureVisuals(
    uv=np.vstack([p.visual.uv for p in parts]),
    material=trimesh.visual.material.SimpleMaterial(image=img),
)
mesh.visual = tex
# ground it: bottom at y=0, ~2 units tall (≈ Roblox scale 2 studs)
mesh.apply_translation((0, -mesh.bounds[0][1], 0))
mesh.apply_scale(2.0 / mesh.extents[1])

mesh.export(f"{OUT}/puffpaw.glb")
mesh.export(f"{OUT}/puffpaw.obj")
print("triangles:", len(mesh.faces), "extents:", mesh.extents.round(2))

# preview render (matplotlib, simple lambert)
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
fig = plt.figure(figsize=(8, 4), dpi=150)
cols = np.vstack([np.tile(np.array(PAL[c]) / 255, (len(p.faces), 1)) for p, c in
                  zip(parts, [names[int(p.visual.uv[0][0] * img.width // 16)] for p in parts])])
light = np.array([0.3, 0.7, 0.8]); light /= np.linalg.norm(light)
for k, (az, title) in enumerate(((55, "3/4"), (90, "front"))):
    ax = fig.add_subplot(1, 2, k + 1, projection="3d")
    tri = mesh.vertices[mesh.faces][:, :, [0, 2, 1]]  # map Y-up to mpl Z-up
    n = mesh.face_normals[:, [0, 2, 1]]
    L = light[[0, 2, 1]]
    if az == -90: pass
    shade = 0.7 + 0.3 * np.clip(n @ L, 0, 1)
    ax.add_collection3d(Poly3DCollection(tri, facecolors=np.clip(cols * shade[:, None], 0, 1), linewidths=0))
    r = 1.2
    ax.set_xlim(-r, r); ax.set_ylim(-r, r); ax.set_zlim(0, 2 * r)
    ax.view_init(elev=12, azim=az); ax.set_box_aspect((1, 1, 1)); ax.axis("off"); ax.set_title(title)
plt.tight_layout(); plt.savefig(f"{OUT}/puffpaw_preview.png", facecolor="#bfe3ff")
