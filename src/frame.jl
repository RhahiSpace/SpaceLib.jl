module ReferenceFrame

using KRPC
using SpaceLib
import KRPC.Interface.SpaceCenter as SC
import KRPC.Interface.SpaceCenter.Helpers as SCH
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR

"""
    SRF(ves::SCR.Vessel)
    SRF(sp::Spacecraft)

The reference frame that is fixed relative to the vessel, and orientated with
the surface of the body being orbited. The origin is at the center of mass of
the vessel.The axes rotate with the north and up directions on the surface of
the body.The x-axis points in the zenith direction (upwards, normal to the body
being orbited, from the center of the body towards the center of mass of the
vessel).The y-axis points northwards towards the astronomical horizon (north,
and tangential to the surface of the body - the direction in which a compass
would point when on the surface).The z-axis points eastwards towards the
astronomical horizon (east, and tangential to the surface of the body - east on
a compass when on the surface).
"""
SRF(ves::SCR.Vessel) = ves |> SCH.SurfaceReferenceFrame
SRF(sp::Spacecraft) = SRF(sp.ves)

"""
    SVRF(ves::SCR.Vessel)
    SVRF(sp::Spacecraft)

The reference frame that is fixed relative to the vessel, and orientated with
the velocity vector of the vessel relative to the surface of the body being
orbited. The origin is at the center of mass of the vessel.The axes rotate with
the vessel's velocity vector.The y-axis points in the direction of the vessel's
velocity vector, relative to the surface of the body being orbited.The z-axis is
in the plane of the astronomical horizon.The x-axis is orthogonal to the other
two axes.
"""
SVRF(ves::SCR.Vessel) = ves |> SCH.SurfaceVelocityReferenceFrame
SVRF(sp::Spacecraft) = SVRF(sp.ves)

"""
    BCI(body::SCR.CelestialBody)
    BCI(ves::SCR.Vessel)
    BCI(sp::Spacecraft)

The reference frame that is fixed relative to this celestial body, and
orientated in a fixed direction (it does not rotate with the body). The origin
is at the center of the body.The axes do not rotate.The x-axis points in an
arbitrary direction through the equator.The y-axis points from the center of the
body towards the north pole.The z-axis points in an arbitrary direction through
the equator.
"""
BCI(body::SCR.CelestialBody) = SCH.NonRotatingReferenceFrame(body)
BCI(ves::SCR.Vessel) = ves |> SCH.Orbit |> SCH.Body |> SCH.NonRotatingReferenceFrame
BCI(sp::Spacecraft) = BCI(sp.ves)

"""
    BCBF(body::SCR.CelestialBody)
    BCBF(ves::SCR.Vessel)
    BCBF(sp::Spacecraft)

Body centered body focused frame in current body
"""
BCBF(body::SCR.CelestialBody) = SCH.ReferenceFrame(body)
BCBF(ves::SCR.Vessel) = ves |> SCH.Orbit |> SCH.Body |> SCH.ReferenceFrame
BCBF(sp::Spacecraft) = BCBF(sp.ves)

"""
    ORF(ves::SCR.Vessel)
    ORF(sp::Spacecraft)

The reference frame that is fixed relative to the vessel, and orientated with
the vessels orbital prograde/normal/radial directions. The origin is at the
center of mass of the vessel.The a@xes rotate with the orbital
prograde/normal/radial directions.The x-axis points in the orbital anti-radial
direction.The y-axis points in the orbital prograde direction.The z-axis points
in the orbital normal direction.
"""
ORF(ves::SCR.Vessel) = ves |> SCH.OrbitalReferenceFrame
ORF(sp::Spacecraft) = ORF(sp.ves)

"""
    COMF(part::SCR.Part)

The reference frame that is fixed relative to this part, and centered on its
center of mass. The origin is at the center of mass of the part, as returned by
?. The axes rotate with the part. The x, y and z axis directions depend on the
design of the part.
"""
COMF(part::SCR.Part) = part |> SCH.CenterOfMassReferenceFrame

"""
    TRF(thruster::SCR.Thruster)

A reference frame that is fixed relative to the thruster and orientated with its
thrust direction (). For gimballed engines, this takes into account the current
rotation of the gimbal.

The origin is at the position of thrust for this thruster (). The axes rotate
with the thrust direction. This is the direction in which the thruster expels
propellant, including any gimballing. The y-axis points along the thrust
direction. The x-axis and z-axis are perpendicular to the thrust direction.
"""
TRF(thruster::SCR.Thruster) = thruster |> SCH.ThrustReferenceFrame

end
