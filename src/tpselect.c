/* SPDX-License-Identifier: GPL-2.0 */
/*
 * tpselect -- installed AS /lib/modules/cyttsp5.ko
 *
 * tp-calibrate.sh always insmods that path. This module must never hang
 * the boot logo. It powers the digitizer, pulses RST, then:
 *   hello 55 at 0x10  -> insmod elankc1.driver.ko
 *   ACK at 0x24       -> insmod cyttsp5.driver.ko
 *   neither           -> leave, desktop still comes up
 *
 * Internal name is tpselect, not cyttsp5, so the stock Cypress module
 * can load afterwards. Do not i2c_new_dummy 0x34 (AXP is already claimed).
 */
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/gpio.h>
#include <linux/i2c.h>
#include <linux/kmod.h>
#include <linux/module.h>
#include <linux/string.h>

#define NAME			"tpselect"
#define AXP_ADDR		0x34
#define AXP_BUS			0
#define TOUCH_BUS		2
#define ELAN_ADDR		0x10
#define CY_ADDR			0x24
#define RST_GPIO		48

#define AXP_LDOIO0_CTL		0x90
#define AXP_LDOIO0_VOLT		0x91
#define AXP_LDOIO1_CTL		0x92
#define AXP_LDOIO1_VOLT		0x93
#define AXP_FUNC_ON		0x03

#define ELAN_KO		"/lib/modules/elankc1.driver.ko"
#define STOCK_KO	"/lib/modules/cyttsp5.driver.ko"
#define ACCESS_KO	"/lib/modules/cyttsp5_device_access.driver.ko"
/* Pre-0.1 names, if install has not migrated yet. */
#define ELAN_KO_OLD	"/lib/modules/elankc1.ko"
#define STOCK_OLD	"/lib/modules/cyttsp5.stock.ko"
#define STOCK_BAK	"/lib/modules/cyttsp5.ko.bak"
#define ACCESS_OLD	"/lib/modules/cyttsp5_device_access.stock.ko"

static int axp_rw(struct i2c_adapter *adap, u8 reg, u8 *val, int wr)
{
	struct i2c_msg m[2];
	u8 wb[2];
	int n;

	if (!adap)
		return -ENODEV;

	if (wr) {
		wb[0] = reg;
		wb[1] = *val;
		m[0].addr = AXP_ADDR;
		m[0].flags = 0;
		m[0].len = 2;
		m[0].buf = wb;
		n = i2c_transfer(adap, m, 1);
		return n == 1 ? 0 : (n < 0 ? n : -EIO);
	}

	wb[0] = reg;
	m[0].addr = AXP_ADDR;
	m[0].flags = 0;
	m[0].len = 1;
	m[0].buf = wb;
	m[1].addr = AXP_ADDR;
	m[1].flags = I2C_M_RD;
	m[1].len = 1;
	m[1].buf = val;
	n = i2c_transfer(adap, m, 2);
	return n == 2 ? 0 : (n < 0 ? n : -EIO);
}

static int axp_ldo_on(struct i2c_adapter *adap, u8 ctl, u8 volt_reg)
{
	u8 v = 0, w;
	int r;

	r = axp_rw(adap, volt_reg, &v, 0);
	if (r < 0)
		return r;
	if ((v & 0x1f) < 0x0a) {
		v = 0x1a;
		axp_rw(adap, volt_reg, &v, 1);
	}
	r = axp_rw(adap, ctl, &v, 0);
	if (r < 0)
		return r;
	w = (u8)((v & ~7u) | AXP_FUNC_ON);
	return axp_rw(adap, ctl, &w, 1);
}

static void power_touch(void)
{
	struct i2c_adapter *adap;
	int i;

	for (i = 0; i < 40; i++) {
		adap = i2c_get_adapter(AXP_BUS);
		if (adap)
			break;
		msleep(100);
	}
	if (!adap) {
		pr_warn(NAME ": no AXP adapter\n");
		return;
	}
	axp_ldo_on(adap, AXP_LDOIO0_CTL, AXP_LDOIO0_VOLT);
	msleep(40);
	axp_ldo_on(adap, AXP_LDOIO1_CTL, AXP_LDOIO1_VOLT);
	msleep(80);
	i2c_put_adapter(adap);
}

static void pulse_rst(void)
{
	int r = gpio_request(RST_GPIO, "tpselect_rst");

	if (r && r != -EBUSY)
		pr_warn(NAME ": rst gpio %d request %d\n", RST_GPIO, r);
	gpio_direction_output(RST_GPIO, 1);
	gpio_set_value(RST_GPIO, 0);
	msleep(200);
	gpio_set_value(RST_GPIO, 1);
	msleep(20);
	gpio_free(RST_GPIO);
}

static int i2c_rd(struct i2c_adapter *adap, u16 addr, u8 *buf, int len)
{
	struct i2c_msg m;

	m.addr = addr;
	m.flags = I2C_M_RD;
	m.len = (u16)len;
	m.buf = buf;
	return i2c_transfer(adap, &m, 1);
}

static int is_hello(const u8 *b)
{
	return b[0] == 0x55 && b[1] == 0x55 &&
	       b[2] == 0x55 && b[3] == 0x55;
}

static int elan_hello(struct i2c_adapter *adap)
{
	u8 buf[4];
	int i, r;

	for (i = 0; i < 12; i++) {
		memset(buf, 0xcc, 4);
		r = i2c_rd(adap, ELAN_ADDR, buf, 4);
		pr_info(NAME ": 0x10 try %d xfer=%d %02x %02x %02x %02x\n",
			i, r, buf[0], buf[1], buf[2], buf[3]);
		if (r == 1 && is_hello(buf))
			return 1;
		msleep(40);
	}
	return 0;
}

static int cypress_ack(struct i2c_adapter *adap)
{
	u8 b = 0;
	int r = i2c_rd(adap, CY_ADDR, &b, 1);

	pr_info(NAME ": 0x24 ping xfer=%d byte=%02x\n", r, b);
	return r == 1;
}

static int file_ok(const char *path)
{
	struct file *f = filp_open(path, O_RDONLY, 0);

	if (IS_ERR(f))
		return 0;
	filp_close(f, NULL);
	return 1;
}

static int insmod_path(const char *path)
{
	char *argv_sm[] = { "/sbin/insmod", (char *)path, NULL };
	char *argv_bb[] = { "/bin/busybox", "insmod", (char *)path, NULL };
	char *envp[] = {
		"HOME=/",
		"PATH=/sbin:/usr/sbin:/bin:/usr/bin",
		NULL
	};
	int r;

	if (!file_ok(path)) {
		pr_err(NAME ": missing %s\n", path);
		return -ENOENT;
	}
	r = call_usermodehelper(argv_sm[0], argv_sm, envp, UMH_WAIT_PROC);
	if (r) {
		pr_info(NAME ": /sbin/insmod %s -> %d, try busybox\n",
			path, r);
		r = call_usermodehelper(argv_bb[0], argv_bb, envp,
					UMH_WAIT_PROC);
	}
	pr_info(NAME ": insmod %s -> %d\n", path, r);
	return r;
}

static int __init tpselect_init(void)
{
	struct i2c_adapter *adap;
	int i;

	pr_info(NAME ": probe Elan 0x10 / Cypress 0x24\n");
	power_touch();
	pulse_rst();

	for (i = 0; i < 20; i++) {
		adap = i2c_get_adapter(TOUCH_BUS);
		if (adap)
			break;
		msleep(100);
	}
	if (!adap) {
		pr_err(NAME ": no TWI%d -- not hanging\n", TOUCH_BUS);
		return 0;
	}

	if (elan_hello(adap)) {
		i2c_put_adapter(adap);
		pr_info(NAME ": Elan hello -- load driver\n");
		if (file_ok(ELAN_KO))
			insmod_path(ELAN_KO);
		else
			insmod_path(ELAN_KO_OLD);
		return 0;
	}
	if (cypress_ack(adap)) {
		i2c_put_adapter(adap);
		pr_info(NAME ": Cypress ACK -- load driver\n");
		if (file_ok(STOCK_KO))
			insmod_path(STOCK_KO);
		else if (file_ok(STOCK_OLD))
			insmod_path(STOCK_OLD);
		else
			insmod_path(STOCK_BAK);
		if (file_ok(ACCESS_KO))
			insmod_path(ACCESS_KO);
		else if (file_ok(ACCESS_OLD))
			insmod_path(ACCESS_OLD);
		return 0;
	}
	i2c_put_adapter(adap);
	pr_info(NAME ": no digitizer -- boot continues\n");
	return 0;
}

static void __exit tpselect_exit(void)
{
}

module_init(tpselect_init);
module_exit(tpselect_exit);

MODULE_AUTHOR("PB740-2 touch select");
MODULE_DESCRIPTION("Select Elan or stock Cypress touch; never block boot");
MODULE_LICENSE("GPL");
