#import "Basic";
#import "Math";

#scope_export

SamplerState :: #type,distinct s32;
Texture1D :: struct { Sample: #type (sampler: SamplerState, tex_coord: float32) -> Vector4; };
Texture2D :: struct { Sample: #type (sampler: SamplerState, tex_coord: Vector3) -> Vector4; };
Texture3D :: struct { Sample: #type (sampler: SamplerState, tex_coord: Vector3) -> Vector4; };

IVector2 :: struct { x, y: s32; }
IVector3 :: struct { x, y, z: s32; }
IVector4 :: struct { x, y, z, w: s32; }
UVector2 :: struct { x, y: u32; }
UVector3 :: struct { x, y, z: u32; }
UVector4 :: struct { x, y, z, w: u32; }
BVector2 :: struct { x, y: bool; }
BVector3 :: struct { x, y, z: bool; }
BVector4 :: struct { x, y, z, w: bool; }

Sampler1D :: #type,distinct s32;
Sampler2D :: #type,distinct s32;
Sampler3D :: #type,distinct s32;

floor :: inline (v: Vector2) -> Vector2 { return Vector2.{ floor(v.x), floor(v.y) }; }
floor :: inline (v: Vector3) -> Vector3 { return Vector3.{ floor(v.x), floor(v.y), floor(v.z) }; }
floor :: inline (v: Vector4) -> Vector4 { return Vector4.{ floor(v.x), floor(v.y), floor(v.z), floor(v.w) }; }

radians :: inline (degrees: $T) -> T {
  #assert T == float || T == float64;
  return degrees * xx (3.1415926535 / 180);
}
radians :: inline (v: Vector2) -> Vector2 { return Vector2.{ radians(v.x), radians(v.y) }; }
radians :: inline (v: Vector3) -> Vector3 { return Vector3.{ radians(v.x), radians(v.y), radians(v.z) }; }
radians :: inline (v: Vector4) -> Vector4 { return Vector4.{ radians(v.x), radians(v.y), radians(v.z), radians(v.w) }; }

degrees :: inline (radians: $T) -> T {
  #assert T == float || T == float64;
  return radians * xx (180 / 3.1415926535);
}
degrees :: inline (v: Vector2) -> Vector2 { return Vector2.{ degrees(v.x), degrees(v.y) }; }
degrees :: inline (v: Vector3) -> Vector3 { return Vector3.{ degrees(v.x), degrees(v.y), degrees(v.z) }; }
degrees :: inline (v: Vector4) -> Vector4 { return Vector4.{ degrees(v.x), degrees(v.y), degrees(v.z), degrees(v.w) }; }

exp2 :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return xx pow(2, x);
}
exp2 :: inline (v: Vector2) -> Vector2 { return Vector2.{ exp2(v.x), exp2(v.y) }; }
exp2 :: inline (v: Vector3) -> Vector3 { return Vector3.{ exp2(v.x), exp2(v.y), exp2(v.z) }; }
exp2 :: inline (v: Vector4) -> Vector4 { return Vector4.{ exp2(v.x), exp2(v.y), exp2(v.z), exp2(v.w) }; }

fma :: inline (a: $T, b: T, c: T) -> T {
  #assert T == float || T == float64;
  return a * b + c;
}
fma :: inline (a: Vector2, b: Vector2, c: Vector2) -> Vector2 { return Vector2.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y) }; }
fma :: inline (a: Vector3, b: Vector3, c: Vector3) -> Vector3 { return Vector3.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z) }; }
fma :: inline (a: Vector4, b: Vector4, c: Vector4) -> Vector4 { return Vector4.{ fma(a.x, b.x, c.x), fma(a.y, b.y, c.y), fma(a.z, b.z, c.z), fma(a.w, b.w, c.w) }; }

fract :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return x - floor(x);
}
fract :: inline (v: Vector2) -> Vector2 { return Vector2.{ fract(v.x), fract(v.y) }; }
fract :: inline (v: Vector3) -> Vector3 { return Vector3.{ fract(v.x), fract(v.y), fract(v.z) }; }
fract :: inline (v: Vector4) -> Vector4 { return Vector4.{ fract(v.x), fract(v.y), fract(v.z), fract(v.w) }; }

inversesqrt :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return 1 / sqrt(x);
}
inversesqrt :: inline (v: Vector2) -> Vector2 { return Vector2.{ inversesqrt(v.x), inversesqrt(v.y) }; }
inversesqrt :: inline (v: Vector3) -> Vector3 { return Vector3.{ inversesqrt(v.x), inversesqrt(v.y), inversesqrt(v.z) }; }
inversesqrt :: inline (v: Vector4) -> Vector4 { return Vector4.{ inversesqrt(v.x), inversesqrt(v.y), inversesqrt(v.z), inversesqrt(v.w) }; }

log2 :: inline (x: $T) -> T {
  #assert T == float || T == float64;
  return log(x) / log(2);
}
log2 :: inline (v: Vector2) -> Vector2 { return Vector2.{ log2(v.x), log2(v.y) }; }
log2 :: inline (v: Vector3) -> Vector3 { return Vector3.{ log2(v.x), log2(v.y), log2(v.z) }; }
log2 :: inline (v: Vector4) -> Vector4 { return Vector4.{ log2(v.x), log2(v.y), log2(v.z), log2(v.w) }; }

mix :: (x: $T, y: T, t: $M) -> T #expand {
  #assert (T == float || T == float64) && (M == float || M == float64 || M == bool);
  return lerp(x, y, xx t);
}
mix :: inline (a: Vector2, b: Vector2, m: BVector2) -> Vector2 { return Vector2.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y) }; }
mix :: inline (a: Vector3, b: Vector3, m: BVector3) -> Vector3 { return Vector3.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y), mix(a.z, b.z, m.z) }; }
mix :: inline (a: Vector4, b: Vector4, m: BVector4) -> Vector4 { return Vector4.{ mix(a.x, b.x, m.x), mix(a.y, b.y, m.y), mix(a.z, b.z, m.z), mix(a.w, b.w, m.w) }; }

mod :: inline (x: $T, y: T) -> T {
  #assert T == float || T == float64;
  return x - y * floor(x / y);
}
mod :: inline (a: Vector2, b: Vector2) -> Vector2 { return Vector2.{ mod(a.x, b.x), mod(a.y, b.y) }; }
mod :: inline (a: Vector3, b: Vector3) -> Vector3 { return Vector3.{ mod(a.x, b.x), mod(a.y, b.y), mod(a.z, b.z) }; }
mod :: inline (a: Vector4, b: Vector4) -> Vector4 { return Vector4.{ mod(a.x, b.x), mod(a.y, b.y), mod(a.z, b.z), mod(a.w, b.w) }; }

round :: (x: $T) -> T {
  #assert T == float || T == float64;
  if x - floor(x) > 0.5 return ceil(x);
  else return floor(x);
}
round :: inline (v: Vector2) -> Vector2 { return Vector2.{ round(v.x), round(v.y) }; }
round :: inline (v: Vector3) -> Vector3 { return Vector3.{ round(v.x), round(v.y), round(v.z) }; }
round :: inline (v: Vector4) -> Vector4 { return Vector4.{ round(v.x), round(v.y), round(v.z), round(v.w) }; }

roundEven :: (x: $T) -> T {
  #assert T == float || T == float64;
  pivot := x - floor(x);
  if pivot > 0.5 return ceil(x);
  else if pivot < 0.5 return floor(x);
  else return ifx is_even(ceil(x)) then ceil(x) else floor(x);
}
roundEven :: inline (v: Vector2) -> Vector2 { return Vector2.{ roundEven(v.x), roundEven(v.y) }; }
roundEven :: inline (v: Vector3) -> Vector3 { return Vector3.{ roundEven(v.x), roundEven(v.y), roundEven(v.z) }; }
roundEven :: inline (v: Vector4) -> Vector4 { return Vector4.{ roundEven(v.x), roundEven(v.y), roundEven(v.z), roundEven(v.w) }; }

sign :: (x: $T) -> T
#modify { return is_number(T); }
{
  if x == 0 return 0;
  return ifx x < 0 then -1 else xx 1;
}
sign :: inline (v: $T) -> T { #assert T == Vector2 || T == IVector2 || T == UVector2; return Vector2.{ sign(v.x), sign(v.y) }; }
sign :: inline (v: $T) -> T { #assert T == Vector3 || T == IVector3 || T == UVector3; return Vector3.{ sign(v.x), sign(v.y), sign(v.z) }; }
sign :: inline (v: $T) -> T { #assert T == Vector4 || T == IVector4 || T == UVector4; return Vector4.{ sign(v.x), sign(v.y), sign(v.z), sign(v.w) }; }

smoothstep :: inline (edge0: $T, edge1: T, x: T) -> T {
  #assert T == float || T == float64;
  t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
smoothstep :: inline (a: Vector2, b: Vector2, t: Vector2) -> Vector2 { return Vector2.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y) }; }
smoothstep :: inline (a: Vector3, b: Vector3, t: Vector3) -> Vector3 { return Vector3.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y), smoothstep(a.z, b.z, t.z) }; }
smoothstep :: inline (a: Vector4, b: Vector4, t: Vector4) -> Vector4 { return Vector4.{ smoothstep(a.x, b.x, t.x), smoothstep(a.y, b.y, t.y), smoothstep(a.z, b.z, t.z), smoothstep(a.w, b.w, t.w) }; }

step :: (edge: $T, x: T) -> T {
  #assert T == float || T == float64;
  return ifx x < edge then 0.0 else 1.0;
}
step :: inline (edge: Vector2, x: Vector2) -> Vector2 { return Vector2.{ step(edge.x, x.x), step(edge.y, x.y) }; }
step :: inline (edge: Vector3, x: Vector3) -> Vector3 { return Vector3.{ step(edge.x, x.x), step(edge.y, x.y), step(edge.z, x.z) }; }
step :: inline (edge: Vector4, x: Vector4) -> Vector4 { return Vector4.{ step(edge.x, x.x), step(edge.y, x.y), step(edge.z, x.z), step(edge.w, x.w) }; }

trunc :: inline (x: $T) -> T { #assert T == float || T == float64; return floor(x); };
trunc :: inline (v: Vector2) -> Vector2 { return Vector2.{ trunc(v.x), trunc(v.y) }; }
trunc :: inline (v: Vector3) -> Vector3 { return Vector3.{ trunc(v.x), trunc(v.y), trunc(v.z) }; }
trunc :: inline (v: Vector4) -> Vector4 { return Vector4.{ trunc(v.x), trunc(v.y), trunc(v.z), trunc(v.w) }; }

equal :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x == b.x, a.y == b.y }; }
equal :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x == b.x, a.y == b.y, a.z == b.z }; }
equal :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x == b.x, a.y == b.y, a.z == b.z, a.w == b.w }; }

faceforward :: inline (N: $T, I: T, Nref: T) -> T {
  return T == Vector2 || T == Vector3 || T == Vector4;
  return ifx dot(Nref, I) < 0 then N else -N;
}

normalize :: inline (v: $T) -> T {
  #assert T == Vector2 || T == Vector3 || T == Vector4;
  return v / length(v);
}

notEqual :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x != b.x, a.y != b.y }; }
notEqual :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x != b.x, a.y != b.y, a.z != b.z }; }
notEqual :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x != b.x, a.y != b.y, a.z != b.z, a.w != b.w }; }

reflect :: (I: $T, N: T) -> T {
  #assert T == Vector2 || T == Vector3 || T == Vector4;
  return I - 2 * dot(N, I) * N;
}

refract :: (I: $T, N: T, eta: float) -> T {
  #assert T == Vector2 || T == Vector3 || T == Vector4;
  k := 1.0 - eta * eta * (1.0 - dot(N, I) * dot(N, I));
  if (k < 0.0)
      return .{};
  else
      return eta * I - (eta * dot(N, I) + sqrt(k)) * N;
}

all :: inline (v: BVector2) -> bool { return v.x && v.y; }
all :: inline (v: BVector3) -> bool { return v.x && v.y && v.z; }
all :: inline (v: BVector4) -> bool { return v.x && v.y && v.z && v.w; }
any :: inline (v: BVector2) -> bool { return v.x || v.y; }
any :: inline (v: BVector3) -> bool { return v.x || v.y || v.z; }
any :: inline (v: BVector4) -> bool { return v.x || v.y || v.z || v.w; }
greaterThan :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x > b.x, a.y > b.y }; }
greaterThan :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x > b.x, a.y > b.y, a.z > b.z }; }
greaterThan :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x > b.x, a.y > b.y, a.z > b.z, a.w > b.w }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x >= b.x, a.y >= b.y }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x >= b.x, a.y >= b.y, a.z >= b.z }; }
greaterThanEqual :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x >= b.x, a.y >= b.y, a.z >= b.z, a.w >= b.w }; }
lessThan :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x < b.x, a.y < b.y }; }
lessThan :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x < b.x, a.y < b.y, a.z < b.z }; }
lessThan :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x < b.x, a.y < b.y, a.z < b.z, a.w < b.w }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector2 { #assert T == Vector2 || T == IVector2 || T == UVector2; return BVector2.{ a.x <= b.x, a.y <= b.y }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector3 { #assert T == Vector3 || T == IVector3 || T == UVector3; return BVector3.{ a.x <= b.x, a.y <= b.y, a.z <= b.z }; }
lessThanEqual :: inline (a: $T, b: T) -> BVector4 { #assert T == Vector4 || T == IVector4 || T == UVector4; return BVector4.{ a.x <= b.x, a.y <= b.y, a.z <= b.z, a.w <= b.w }; }
not :: inline (v: BVector2) -> BVector2 { return BVector2.{ !v.x, !v.y }; }
not :: inline (v: BVector3) -> BVector3 { return BVector3.{ !v.x, !v.y, !v.z }; }
not :: inline (v: BVector4) -> BVector4 { return BVector4.{ !v.x, !v.y, !v.z, !v.w }; }

texture :: (sampler: $T, point: $S, bias: float = 0) -> Vector4 {
  #assert (T == Sampler1D && S == float) || (T == Sampler2D && S == Vector2) || (T == Sampler3D && S == Vector3);
}

is_number :: (T: Type) -> bool {
  return T == float ||
         T == float64 ||
         T == int ||
         T == s8  ||
         T == s16 ||
         T == s32 ||
         T == s64 ||
         T == u8  ||
         T == u16 ||
         T == u32 ||
         T == u64;
}
is_even :: (v: float) -> bool { return (cast(s32) floor(v)) % 2 == 0; }
is_even :: (v: float64) -> bool { return (cast(s32) floor(v)) % 2 == 0; }
