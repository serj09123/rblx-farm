"""Procedural low-poly critters for Skyheart Ranch -> GLB (palette texture) + preview sheet.

Usage:  python critters.py OUTDIR [species_id ...]      (no ids = every species with a recipe)

* Colours come from src/shared/config/Creatures.luau (`color` = body, `accent`).
* Style contract (same as the original Puffpaw): round body with tiny fur wobble, big dark
  eyes with two highlights, blush, little nose, bean paws. Front = +Z (Roblox shows it as -Z),
  Y up, feet on y = 0, largest dimension normalised to 2 units (code rescales to species.scale).
* One mesh, one 8x? palette texture, <= ~6k triangles. Add a species = write a recipe below.
"""
import os
import re
import sys

import numpy as np
import trimesh
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CREATURES_LUAU = os.path.join(ROOT, "src", "shared", "config", "Creatures.luau")


# --------------------------------------------------------------------------- data
def load_species():
    text = open(CREATURES_LUAU).read()
    out = {}
    pat = re.compile(
        r'id = "(\w+)",\s*displayName = "([^"]+)",\s*rarity = "(\w+)",\s*baseValue = \d+,\s*'
        r"color = \{ ([\d, ]+) \},\s*accent = \{ ([\d, ]+) \},\s*shape = \"(\w+)\",\s*scale = ([\d.]+)"
    )
    for m in pat.finditer(text):
        i, name, rarity, col, acc, shape, scale = m.groups()
        out[i] = dict(
            id=i,
            name=name,
            rarity=rarity,
            color=tuple(int(x) for x in col.split(",")),
            accent=tuple(int(x) for x in acc.split(",")),
            shape=shape,
            scale=float(scale),
        )
    return out


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


WHITE = (255, 255, 255)
BLACK = (0, 0, 0)


def palette_for(sp, eye=(30, 24, 48)):
    base, acc = sp["color"], sp["accent"]
    return {
        "base": base,
        "base2": mix(base, WHITE, 0.38),  # belly / inner tones
        "dark": mix(base, BLACK, 0.28),  # paws, shading details
        "accent": acc,
        "accent2": mix(acc, WHITE, 0.45),
        "accentd": mix(acc, BLACK, 0.3),
        "eye": eye,
        "white": WHITE,
        "nose": mix(base, (235, 110, 150), 0.7),
        "blush": mix(base, (255, 140, 175), 0.6),
    }


# --------------------------------------------------------------------------- builder
class Builder:
    def __init__(self, colors, seed=7):
        self.colors = colors
        self.names = list(colors)
        self.parts = []  # (mesh, colour name)
        self.rng = np.random.default_rng(seed)

    def add(self, mesh, name):
        self.parts.append((mesh, name))
        return mesh

    # primitives ---------------------------------------------------------------
    def ell(self, r, c=(0, 0, 0), s=(1, 1, 1), name="base", sub=2, rot=None):
        m = trimesh.creation.icosphere(subdivisions=sub, radius=r)
        m.vertices *= s
        if rot is not None:
            m.apply_transform(trimesh.transformations.euler_matrix(*rot))
        m.apply_translation(c)
        return self.add(m, name)

    def cone(self, r, h, base=(0, 0, 0), d=(0, 1, 0), name="accent", sections=10):
        m = trimesh.creation.cone(radius=r, height=h, sections=sections)
        m.apply_transform(trimesh.geometry.align_vectors([0, 0, 1], np.array(d, float)))
        m.apply_translation(base)
        return self.add(m, name)

    def cyl(self, r, h, c=(0, 0, 0), d=(0, 1, 0), name="accent", sections=8):
        m = trimesh.creation.cylinder(radius=r, height=h, sections=sections)
        m.apply_transform(trimesh.geometry.align_vectors([0, 0, 1], np.array(d, float)))
        m.apply_translation(c)
        return self.add(m, name)

    def body(self, radii, c=(0, 0, 0), fluff=0.045, name="base", sub=3):
        """Fluffy ellipsoid; returns an `on_surface(x, y)` helper for placing face details."""
        m = trimesh.creation.icosphere(subdivisions=sub, radius=1.0)
        v = m.vertices
        d = np.sin(v[:, 0] * 7) * np.sin(v[:, 1] * 6 + 1) * np.sin(v[:, 2] * 7 + 2)
        v = v * (1 + fluff * d + self.rng.normal(0, fluff * 0.13, len(v)))[:, None]
        m.vertices = v * radii
        m.apply_translation(c)
        self.add(m, name)
        rx, ry, rz = radii

        def on_surface(x, y, back=False):
            q = 1 - (x / rx) ** 2 - ((y - c[1]) / ry) ** 2
            z = rz * np.sqrt(max(q, 0.0)) * (-1 if back else 1)
            return (x, y, c[2] + z)

        return on_surface

    # common features ----------------------------------------------------------
    def face(self, surf, y, spread=0.33, size=0.17, nose=True, blush=True, eye="eye"):
        for s in (-1, 1):
            ex, ey, ez = surf(s * spread, y)
            self.ell(size, (ex, ey, ez - 0.02), (0.9, 1.15, 0.5), name=eye)
            self.ell(size * 0.32, (ex + size * 0.3, ey + size * 0.55, ez + size * 0.5), name="white", sub=1)
            self.ell(size * 0.15, (ex - size * 0.25, ey - size * 0.55, ez + size * 0.55), name="white", sub=1)
            if blush:
                bx, by, bz = surf(s * (spread + 0.23), y - 0.2)
                self.ell(size * 0.65, (bx, by, bz - 0.04), (1, 0.6, 0.35), name="blush", sub=1)
        if nose:
            nx, ny, nz = surf(0, y - 0.14)
            self.ell(0.06, (nx, ny, nz - 0.02), (1.3, 0.8, 0.7), name="nose", sub=1)

    def paws(self, spots, r=0.2, y=None, name="dark"):
        for x, z, py in spots:
            self.ell(r, (x, py if y is None else y, z), (1, 0.6, 1.1), name=name)

    def chain(self, pts, radii, name="base", sub=2):
        for p, r in zip(pts, radii):
            self.ell(r, p, name=name, sub=sub)

    # output -------------------------------------------------------------------
    def finish(self, size=2.0):
        n = len(self.names)
        img = Image.new("RGB", (16 * n, 16))
        for i, k in enumerate(self.names):
            img.paste(self.colors[k], (i * 16, 0, i * 16 + 16, 16))
        metas = []
        for mesh, name in self.parts:
            i = self.names.index(name)
            uv = np.tile([(i * 16 + 8) / img.width, 0.5], (len(mesh.vertices), 1))
            mesh.visual = trimesh.visual.TextureVisuals(uv=uv)
            metas.append((len(mesh.faces), name))
        mesh = trimesh.util.concatenate([m for m, _ in self.parts])
        mesh.visual = trimesh.visual.TextureVisuals(
            uv=np.vstack([m.visual.uv for m, _ in self.parts]),
            material=trimesh.visual.material.SimpleMaterial(image=img),
        )
        mesh.apply_translation((0, -mesh.bounds[0][1], 0))
        mesh.apply_scale(size / mesh.extents.max())
        # per-face colours for the preview (after scaling; same face order)
        cols = np.vstack([np.tile(np.array(self.colors[nm]) / 255.0, (nf, 1)) for nf, nm in metas])
        return mesh, cols


# --------------------------------------------------------------------------- recipes
def bubbloo(b, sp):
    """Round water-drop critter: smooth blue body, white bubbles, little side fins."""
    surf = b.body((1.0, 0.95, 1.0), fluff=0.015)
    b.cone(0.3, 0.55, (0, 0.88, 0), (0, 1, 0.1), name="base2")  # water-drop tuft
    for p, r in (((0.38, 0.78, 0.2), 0.14), ((-0.32, 0.84, 0.05), 0.1), ((0.1, 0.98, -0.2), 0.08)):
        b.ell(r, p, name="white", sub=1)  # floating bubbles
    for s in (-1, 1):
        b.ell(0.3, (s * 0.98, -0.05, 0.0), (0.3, 0.7, 1.0), name="accent2", rot=(0, 0, s * 0.5))  # fins
    b.ell(0.55, (0, -0.25, 0.4), (1, 0.8, 0.6), name="base2")  # belly
    b.face(surf, 0.1, spread=0.34, size=0.18)
    b.paws(((-0.4, 0.4, -0.88), (0.4, 0.4, -0.88), (-0.42, -0.3, -0.86), (0.42, -0.3, -0.86)), name="base2")
    b.ell(0.17, (0, -0.4, -0.95), name="accent2")  # tail bubble


def thornback(b, sp):
    """Chunky critter with a mossy shell on its back covered in spikes."""
    surf = b.body((1.05, 0.88, 1.08), fluff=0.03, c=(0, 0, 0))
    b.ell(0.95, (0, 0.28, -0.32), (1.0, 0.62, 0.95), name="accent", sub=3)  # shell dome
    b.ell(0.6, (0, 0.5, -0.32), (1.0, 0.5, 0.95), name="accentd", sub=2)  # shell centre plate
    for x, y, z, r in (
        (0, 0.88, -0.32, 0.17), (0.5, 0.72, -0.1, 0.14), (-0.5, 0.72, -0.1, 0.14),
        (0.55, 0.62, -0.6, 0.13), (-0.55, 0.62, -0.6, 0.13), (0, 0.72, -0.78, 0.13),
        (0.9, 0.35, -0.35, 0.11), (-0.9, 0.35, -0.35, 0.11),
    ):
        d = np.array([x, y - 0.1, z + 0.32]); d /= np.linalg.norm(d) + 1e-9
        b.cone(r, r * 2.6, (x, y, z) - d * r * 0.5, d, name="accent2")
    b.face(surf, 0.0, spread=0.36, size=0.17)
    b.ell(0.22, (0, -0.2, 1.0), (1, 0.7, 0.8), name="base2")  # snout
    b.paws(((-0.5, 0.45, -0.82), (0.5, 0.45, -0.82), (-0.55, -0.35, -0.78), (0.55, -0.35, -0.78)), r=0.24)
    b.cone(0.18, 0.5, (0, -0.35, -1.0), (0, 0.2, -1), name="accentd")  # tail


def frostwhisk(b, sp):
    """Slender ice cat: pointy ears, long whiskers, crystal crown and a fluffy ice-tipped tail."""
    surf = b.body((0.88, 0.95, 1.05), fluff=0.05, c=(0, 0.0, 0))
    b.ell(0.55, (0, -0.25, 0.5), (1, 0.85, 0.6), name="base2")
    for s in (-1, 1):
        b.cone(0.3, 0.8, (s * 0.5, 0.7, -0.05), (s * 0.35, 1, -0.1), name="base")  # ears
        b.cone(0.17, 0.55, (s * 0.5, 0.74, 0.08), (s * 0.35, 1, -0.05), name="accent2")
        for k, dy in enumerate((0.1, 0.0, -0.1)):  # whiskers
            ang = (k - 1) * 0.28
            b.cyl(0.018, 0.95, (s * 0.88, -0.05 + dy, 0.62), (s * 1, ang, 0.35), name="accent2", sections=5)
    for x, h, tilt in ((0, 0.95, 0), (0.22, 0.65, 0.45), (-0.22, 0.65, -0.45)):  # ice crown
        b.cone(0.1, h * 0.85, (x * 0.8, 0.82, 0.22), (tilt, 1, 0.1), name="accent")
    b.face(surf, 0.12, spread=0.32, size=0.19, eye="accentd")
    b.paws(((-0.38, 0.5, -0.92), (0.38, 0.5, -0.92), (-0.42, -0.4, -0.9), (0.42, -0.4, -0.9)), name="base2")
    pts = [(0, -0.2, -0.95), (0, -0.05, -1.3), (0, 0.2, -1.55), (0, 0.55, -1.7), (0, 0.9, -1.7)]
    b.chain(pts, (0.22, 0.24, 0.24, 0.22, 0.18), name="base2")
    b.cone(0.16, 0.5, (0, 1.0, -1.7), (0, 1, 0), name="accent")  # ice tip


def emberdrake(b, sp):
    """Small fire drake: horns, little wings, back spines, tail with a flame tip."""
    surf = b.body((0.95, 0.9, 1.1), fluff=0.02, c=(0, 0, 0))
    b.ell(0.62, (0, -0.2, 0.5), (1, 0.95, 0.55), name="accent")  # belly plates
    b.ell(0.32, (0, -0.08, 0.98), (1.15, 0.7, 0.85), name="base2")  # muzzle
    for s in (-1, 1):
        b.cone(0.13, 0.7, (s * 0.35, 0.78, 0.1), (s * 0.35, 1, -0.7), name="accent2")  # horns
        b.ell(0.8, (s * 1.15, 0.45, -0.25), (0.75, 0.06, 0.55), name="accentd", rot=(0, s * 0.35, s * 0.75), sub=2)  # wing membrane
        b.cyl(0.05, 1.15, (s * 1.05, 0.55, -0.1), (s * 0.7, 0.75, 0), name="accent", sections=5)  # wing bone
        b.ell(0.05, (s * 0.13, -0.02, 1.07), name="dark", sub=1)  # nostrils
    for z, h in ((0.2, 0.28), (-0.15, 0.32), (-0.5, 0.3), (-0.8, 0.24)):  # spines
        y = 0.8 * np.sqrt(max(1 - (z / 1.1) ** 2, 0.05)) - 0.02
        b.cone(0.1, h, (0, y, z), (0, 1, -0.25), name="accent")
    b.face(surf, 0.2, spread=0.36, size=0.17, nose=False, blush=False)
    b.paws(((-0.45, 0.5, -0.87), (0.45, 0.5, -0.87), (-0.5, -0.45, -0.85), (0.5, -0.45, -0.85)), r=0.24, name="accentd")
    pts = [(0, -0.35, -1.0), (0, -0.3, -1.35), (0, -0.15, -1.7), (0, 0.05, -1.95)]
    b.chain(pts, (0.3, 0.25, 0.19, 0.14), name="base")
    b.cone(0.22, 0.65, (0, 0.1, -1.98), (0, 0.9, -0.4), name="accent")  # flame
    b.cone(0.12, 0.45, (0, 0.12, -2.0), (0, 0.9, -0.4), name="accent2")


def nimbuswhale(b, sp):
    """Mythic cloud whale: fluffy white body, blue belly, fluke, fins and cloud puffs."""
    surf = b.body((1.25, 0.88, 1.0), fluff=0.06, c=(0, 0, 0))
    b.ell(0.95, (0, -0.28, 0.2), (1.12, 0.6, 0.85), name="accent2")  # blue belly
    for p, r in (((0.0, 0.85, -0.05), 0.42), ((0.5, 0.75, 0.2), 0.32), ((-0.5, 0.78, 0.15), 0.34), ((0.2, 0.8, -0.5), 0.3), ((-0.3, 0.78, -0.5), 0.28)):
        b.ell(r, p, name="base2", sub=1 if r < 0.33 else 2)  # cloud puffs on top
    for s in (-1, 1):
        b.ell(0.45, (s * 1.2, -0.35, 0.2), (0.35, 0.75, 1.0), name="accent", rot=(0, 0, s * 0.7), sub=1)  # fins
        b.ell(0.7, (s * 0.65, 0.1, -1.55), (1.0, 0.18, 0.55), name="accent", rot=(0, s * 0.5, s * 0.25), sub=1)  # fluke
    b.chain([(0, -0.1, -1.0), (0, 0.1, -1.3)], (0.5, 0.32), name="base")
    b.face(surf, 0.1, spread=0.4, size=0.21)
    for x, z in ((-0.5, 0.35), (0.5, 0.35), (-0.55, -0.45), (0.55, -0.45)):
        b.ell(0.3, (x, -0.8, z), (1, 0.6, 1), name="base2", sub=1)  # little cloud feet
    for p, r in (((0.0, 1.5, 0.0), 0.12), ((0.3, 1.45, 0.1), 0.08), ((-0.3, 1.42, 0.05), 0.08)):
        b.ell(r, p, name="accent2", sub=1)  # spout droplets


RECIPES = {
    "bubbloo": bubbloo,
    "thornback": thornback,
    "frostwhisk": frostwhisk,
    "emberdrake": emberdrake,
    "nimbuswhale": nimbuswhale,
}
DARK_EYES = {}  # species whose body is dark may override the eye colour here


# --------------------------------------------------------------------------- output
def preview(items, path):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    rows = len(items)
    fig = plt.figure(figsize=(8, 3.6 * rows), dpi=110)
    light = np.array([0.3, 0.7, 0.8])
    light /= np.linalg.norm(light)
    for r, (sp, mesh, cols) in enumerate(items):
        for k, (az, title) in enumerate(((60, "3/4"), (90, "front"))):
            ax = fig.add_subplot(rows, 2, r * 2 + k + 1, projection="3d")
            tri = mesh.vertices[mesh.faces][:, :, [0, 2, 1]]
            n = mesh.face_normals[:, [0, 2, 1]]
            shade = 0.62 + 0.38 * np.clip(n @ light[[0, 2, 1]], 0, 1)
            ax.add_collection3d(Poly3DCollection(tri, facecolors=np.clip(cols * shade[:, None], 0, 1), linewidths=0))
            lim = 1.1
            ax.set_xlim(-lim, lim)
            ax.set_ylim(-lim, lim)
            ax.set_zlim(0, 2 * lim)
            ax.view_init(elev=12, azim=az)
            ax.set_box_aspect((1, 1, 1))
            ax.axis("off")
            ax.set_title(f"{sp['name']} ({sp['rarity']}) - {title} - {len(mesh.faces)} tris", fontsize=8)
    plt.tight_layout()
    plt.savefig(path, facecolor="#bfe3ff")


def main():
    out = sys.argv[1]
    ids = sys.argv[2:] or list(RECIPES)
    species = load_species()
    os.makedirs(out, exist_ok=True)
    items = []
    for i in ids:
        sp = species[i]
        b = Builder(palette_for(sp, **DARK_EYES.get(i, {})))
        RECIPES[i](b, sp)
        mesh, cols = b.finish()
        d = os.path.join(out, i)
        os.makedirs(d, exist_ok=True)
        mesh.export(os.path.join(d, f"{i}.glb"))
        print(f"{i}: {len(mesh.faces)} triangles, extents {mesh.extents.round(2)}")
        items.append((sp, mesh, cols))
    preview(items, os.path.join(out, "preview_" + ("all" if len(ids) > 1 else ids[0]) + ".png"))


if __name__ == "__main__":
    main()
