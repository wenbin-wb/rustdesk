//! Unix interface enumeration.
//!
//! Vendored from the rustdesk-org/webrtc fork (rev db3b07a) and rewritten to call
//! `libc` directly rather than going through `nix`.
//!
//! Why: `nix` compiles its `mqueue`/`aio`/`personality`/`fs`/`signal` modules on the
//! assumption that `target_os = "linux"` implies glibc. That does not hold for
//! HarmonyOS, whose libc is musl shaped and lacks `mq_open`, `aio_read`, `__fsword_t`,
//! `ST_RELATIME` and friends, so `nix` cannot be compiled for
//! `aarch64-unknown-linux-ohos` at all. This module only ever needed `getifaddrs` and
//! socket-address decoding, both of which `libc` provides on every target we build.

use crate::ifaces::{Interface, Kind, NextHop};

use std::ffi::CStr;
use std::io::Error;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6};

/// Map a `sa_family` to the interface kind we care about.
///
/// Only families that the platforms we build actually define are named here; anything
/// else falls through to `None` and skips that address, matching the previous `nix`
/// based implementation.
fn kind_of(family: libc::c_int) -> Option<Kind> {
    match family {
        libc::AF_INET => Some(Kind::Ipv4),
        libc::AF_INET6 => Some(Kind::Ipv6),
        #[cfg(any(target_os = "android", target_os = "linux"))]
        libc::AF_PACKET => Some(Kind::Packet),
        #[cfg(any(
            target_os = "dragonfly",
            target_os = "freebsd",
            target_os = "ios",
            target_os = "macos",
            target_os = "netbsd",
            target_os = "openbsd"
        ))]
        libc::AF_LINK => Some(Kind::Link),
        _ => None,
    }
}

/// Decode a `sockaddr` into a `SocketAddr`, mirroring `SockaddrStorage::as_sockaddr_in`.
unsafe fn ss_to_netsa(sa: *const libc::sockaddr) -> Option<SocketAddr> {
    if sa.is_null() {
        return None;
    }
    match (*sa).sa_family as libc::c_int {
        libc::AF_INET => {
            let sin = sa as *const libc::sockaddr_in;
            // `s_addr` is in network byte order; read it back as the on-wire octets so
            // the result does not depend on the host's endianness.
            let ip = Ipv4Addr::from((*sin).sin_addr.s_addr.to_ne_bytes());
            Some(SocketAddr::V4(SocketAddrV4::new(
                ip,
                u16::from_be((*sin).sin_port),
            )))
        }
        libc::AF_INET6 => {
            let sin6 = sa as *const libc::sockaddr_in6;
            Some(SocketAddr::V6(SocketAddrV6::new(
                Ipv6Addr::from((*sin6).sin6_addr.s6_addr),
                u16::from_be((*sin6).sin6_port),
                (*sin6).sin6_flowinfo,
                (*sin6).sin6_scope_id,
            )))
        }
        _ => None,
    }
}

/// Query the local system for all interface addresses.
pub fn ifaces() -> Result<Vec<Interface>, Error> {
    let mut ret = Vec::new();

    let mut ifap: *mut libc::ifaddrs = std::ptr::null_mut();
    if unsafe { libc::getifaddrs(&mut ifap) } != 0 {
        return Err(Error::last_os_error());
    }

    let mut cur = ifap;
    while !cur.is_null() {
        let ifa = unsafe { &*cur };
        cur = ifa.ifa_next;

        if ifa.ifa_addr.is_null() {
            continue;
        }
        let Some(kind) = kind_of(unsafe { (*ifa.ifa_addr).sa_family } as libc::c_int) else {
            continue;
        };

        let name = unsafe { CStr::from_ptr(ifa.ifa_name) }
            .to_string_lossy()
            .into_owned();
        let addr = unsafe { ss_to_netsa(ifa.ifa_addr) };
        let mask = unsafe { ss_to_netsa(ifa.ifa_netmask) };
        // `ifa_ifu` is a union: the broadcast address on broadcast links, the peer
        // address on point-to-point links.
        let hop = unsafe { ss_to_netsa(ifa.ifa_ifu) }.map(|sa| {
            if ifa.ifa_flags & libc::IFF_BROADCAST as libc::c_uint != 0 {
                NextHop::Broadcast(sa)
            } else {
                NextHop::Destination(sa)
            }
        });

        ret.push(Interface {
            name,
            kind,
            addr,
            mask,
            hop,
        });
    }

    unsafe { libc::freeifaddrs(ifap) };
    Ok(ret)
}
