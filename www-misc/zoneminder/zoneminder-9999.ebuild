# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# TO DO:
# * dependencies of unknown status:
#	dev-perl/Device-SerialPort #likely to connect to X10 device
#	dev-perl/MIME-Lite #required for zmfilter
#	dev-perl/MIME-tools
#	dev-perl/PHP-Serialization
#	virtual/perl-Archive-Tar
#	virtual/perl-libnet
#	virtual/perl-Module-Load

EAPI=6

inherit versionator perl-functions readme.gentoo-r1 cmake-utils depend.apache flag-o-matic systemd

if [[ ${PV} == 9999 ]] ; then
	MY_PN="${PN}"
	inherit git-r3
	EGIT_REPO_URI="https://github.com/${PN}/${PN}.git"
	KEYWORDS=""
else
	MY_PN="${PN}"
	MY_CRUD_VERSION="3.1.0"
	SRC_URI="
		https://github.com/${PN}/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz
		https://github.com/FriendsOfCake/crud/archive/v${MY_CRUD_VERSION}.tar.gz -> Crud-${MY_CRUD_VERSION}.tar.gz
	"
	KEYWORDS="~amd64"
fi

DESCRIPTION="Capture, analyse, record and monitor any cameras attached to your system"
HOMEPAGE="http://www.zoneminder.com/"

LICENSE="GPL-2"
IUSE="curl ffmpeg gcrypt gnutls +mmap +ssl libressl vlc"
SLOT="0"

REQUIRED_USE="
	|| ( ssl gnutls )
"

DEPEND="
	app-eselect/eselect-php[apache2]
	dev-lang/perl:=
	dev-lang/php:*[apache2,cgi,curl,gd,inifile,pdo,mysql,mysqli,sockets]
	dev-libs/libpcre
	dev-perl/Archive-Zip
	dev-perl/Class-Std-Fast
	dev-perl/Data-Dump
	dev-perl/Date-Manip
	dev-perl/Data-UUID
	dev-perl/DBD-mysql
	dev-perl/DBI
	dev-perl/IO-Socket-Multicast
	dev-perl/SOAP-WSDL
	dev-perl/Sys-CPU
	dev-perl/Sys-MemInfo
	dev-perl/URI-Encode
	dev-perl/libwww-perl
	dev-perl/Sys-CpuLoad
	dev-perl/Format-Human-Bytes
	dev-perl/Number-Bytes-Human
	dev-perl/File-Slurp
	dev-perl/MIME-Lite
	dev-perl/MIME-tools
	dev-perl/PHP-Serialization
	dev-perl/Device-SerialPort
	dev-php/pecl-apcu:*
	sys-auth/polkit
	sys-libs/zlib
	virtual/ffmpeg
	virtual/httpd-php:*
	virtual/jpeg:0
	virtual/mysql
	virtual/perl-ExtUtils-MakeMaker
	virtual/perl-Getopt-Long
	virtual/perl-Sys-Syslog
	virtual/perl-Time-HiRes
	virtual/perl-Archive-Tar
	virtual/perl-libnet
	virtual/perl-Module-Load
	www-servers/apache
	curl? ( net-misc/curl )
	gcrypt? ( dev-libs/libgcrypt:0= )
	gnutls? ( net-libs/gnutls )
	mmap? ( dev-perl/Sys-Mmap )
	ssl? (
		!libressl? ( dev-libs/openssl:0= )
		libressl? ( dev-libs/libressl:0= )
	)
	vlc? ( media-video/vlc[live] )
"
RDEPEND="${DEPEND}"

# we cannot use need_httpd_cgi here, since we need to setup permissions for the
# webserver in global scope (/etc/zm.conf etc), so we hardcode apache here.
need_apache

# MY_PN shows ZoneMinder because extracted folder has uppercase letters (same for git-9999)
S=${WORKDIR}/${MY_PN}-${PV}

MY_ZM_WEBDIR=/usr/share/zoneminder/www
MY_ZM_CACHEDIR=/var/cache/zoneminder

src_prepare() {
	cmake-utils_src_prepare

if [[ ${PV} != 9999 ]] ; then
	rmdir "${S}/web/api/app/Plugin/Crud" || die
	mv "${WORKDIR}/crud-${MY_CRUD_VERSION}" "${S}/web/api/app/Plugin/Crud" || die
fi
}

src_configure() {
	append-cxxflags -D__STDC_CONSTANT_MACROS
	perl_set_version

	mycmakeargs=(
		-DZM_PERL_SUBPREFIX=${VENDOR_LIB#/usr}
		-DZM_TMPDIR=/var/tmp/zm
		-DZM_SOCKDIR=/var/run/zm
		-DZM_WEB_USER=apache
		-DZM_WEB_GROUP=apache
		-DZM_WEBDIR=${MY_ZM_WEBDIR}
		-DZM_NO_MMAP="$(usex mmap OFF ON)"
		-DZM_NO_X10=OFF
		-DZM_NO_FFMPEG="$(usex ffmpeg OFF ON)"
		-DZM_NO_CURL="$(usex curl OFF ON)"
		-DZM_NO_LIBVLC="$(usex vlc OFF ON)"
		-DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL="$(usex ssl OFF ON)"
		-DHAVE_GNUTLS="$(usex gnutls ON OFF)"
		-DHAVE_GCRYPT="$(usex gcrypt ON OFF)"
		-DZM_PATH_ZMS=/zm/cgi-bin/nph-zms
		-DZM_CONFIG_DIR=/etc/zm #new folder #default seems to be /etc which clashes when it installs /etc/.../conf.d/*
		-DZM_CACHEDIR=${MY_ZM_CACHEDIR}
	)

	cmake-utils_src_configure

}

src_install() {
	cmake-utils_src_install

	# the log directory
	keepdir /var/log/zm
	fowners apache:apache /var/log/zm

	# the logrotate script
	insinto /etc/logrotate.d
	newins distros/ubuntu1204/zoneminder.logrotate zoneminder

	# recording folders
	# images and event are defaults in the config - if we want to change them we can use cmake args for ZM_DIR_IMAGES and ZM_DIR_EVENTS
	# ZM_CONFIG_SUBDIR is also cmake arg for /etc/zm/conf.d/ if needed
	keepdir /var/lib/zoneminder /var/lib/zoneminder/images /var/lib/zoneminder/events
	if [[ ${PV} = 9999 ]] ; then
		keepdir /etc/zm
	fi

	fperms -R 0775 /var/lib/zoneminder
	fowners -R apache:apache /var/lib/zoneminder

	# bug 523058 # TODO check remove this bug fix
	keepdir ${MY_ZM_WEBDIR}/temp
	fowners -R apache:apache ${MY_ZM_WEBDIR}

	keepdir ${MY_ZM_CACHEDIR}
	fowners -R apache:apache ${MY_ZM_CACHEDIR}

	# the configuration file
	if [[ ${PV} != 9999 ]] ; then
		fperms 0640 /etc/zm/
		fowners root:apache /etc/zm
	else
		fperms 0640 /etc/zm/zm.conf
		fowners root:apache /etc/zm/zm.conf
	fi

	# init scripts etc
	newinitd "${FILESDIR}"/init.d zoneminder
	newconfd "${FILESDIR}"/conf.d zoneminder

	# systemd unit file
	systemd_dounit "${FILESDIR}"/zoneminder.service

	# copy vhost config to example folder
	cp "${FILESDIR}"/10_zoneminder.conf "${T}"/10_zoneminder.conf || die
	sed -i "${T}"/10_zoneminder.conf -e "s:%ZM_WEBDIR%:${MY_ZM_WEBDIR}:g" || die
	sed -i "${T}"/10_zoneminder.conf -e "s:%ZM_CACHEDIR%:${MY_ZM_CACHEDIR}:g" || die

	# TODO consider removing old symlinks from webroot (images, events)
	# these pose a security risk as there was no security on these folders http://seclists.org/fulldisclosure/2017/Feb/11

	dodoc AUTHORS BUGS ChangeLog INSTALL NEWS README.md TODO "${T}"/10_zoneminder.conf

	perl_delete_packlist

	readme.gentoo_create_doc
}

pkg_postinst() {
	readme.gentoo_print_elog

	local v
	for v in ${REPLACING_VERSIONS}; do
		if ! version_is_at_least ${PV} ${v}; then
			elog "You have upgraded zoneminder and may have to upgrade your database now using the 'zmupdate.pl' script."
		fi
	done
}
