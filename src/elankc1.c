/* SPDX-License-Identifier: GPL-2.0 */
/*
 * elankc1 -- Elan I2C touch for PocketBook 740 Pro + ED078KC1.
 *
 * Not a Cypress driver. Loaded by tpselect (the file named cyttsp5.ko)
 * after hello-55 at 0x10. Registers input name "cyttsp5" for InkView.
 *
 * Missing/NAK chip: init returns -ENODEV and does not stall the boot logo.
 */
#include <linux/delay.h>
#include <linux/gpio.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/workqueue.h>

#define ELAN_NAME		"elankc1"
#define ELAN_INPUT_NAME		"cyttsp5"
#define ELAN_ADDR		0x10
#define ELAN_I2C_BUS		2
#define ELAN_AXP_BUS		0
#define ELAN_AXP_ADDR		0x34
#define ELAN_RST_GPIO		48
#define ELAN_IRQ_GPIO		47

#define RAW_X0			43
#define RAW_X1			1802
#define RAW_Y0			41
#define RAW_Y1			2358
/*
 * Stock cyttsp5 reports CY_MAXX x CY_MAXY = 1872x1404 (EPDC). InkView
 * scales that onto the portrait UI. Emit in that space; rot=1 swaps
 * chip axes so the scale becomes width<-chipY, height<-chipX.
 */
#define SCR_W			1872
#define SCR_H			1404
#define ROT			1

#define AXP_LDOIO0_CTL		0x90
#define AXP_LDOIO0_VOLT		0x91
#define AXP_LDOIO1_CTL		0x92
#define AXP_LDOIO1_VOLT		0x93
#define AXP_LDOIO_FUNC_ON	0x03

static int i2c_bus = ELAN_I2C_BUS;
static int i2c_addr = ELAN_ADDR;
static int axp_bus = ELAN_AXP_BUS;
static int rst_gpio = ELAN_RST_GPIO;
static int irq_gpio = ELAN_IRQ_GPIO;
static int scr_w = SCR_W;
static int scr_h = SCR_H;
static int rot = ROT;

module_param(i2c_bus, int, 0444);
module_param(i2c_addr, int, 0444);
module_param(axp_bus, int, 0444);
module_param(rst_gpio, int, 0444);
module_param(irq_gpio, int, 0444);
module_param(scr_w, int, 0444);
module_param(scr_h, int, 0444);
module_param(rot, int, 0444);

static const u8 cmd_rst[4] = { 0x77, 0x77, 0x77, 0x77 };
static const u8 cmd_main[4] = { 0x4d, 0x61, 0x69, 0x6e };
static const u8 cmd_idle[4] = { 0x54, 0x2c, 0x01, 0x01 };
static const u8 cmd_resume[4] = { 0x54, 0x58, 0x00, 0x01 };

struct elankc1 {
	struct i2c_client *client;
	struct input_dev *input;
	struct delayed_work poll;
	u16 last_x;
	u16 last_y;
	int last_down;
};

static int elan_xfer(struct i2c_client *c, u8 *buf, int len, int rd)
{
	struct i2c_msg m;

	if (!c)
		return -ENODEV;

	m.addr = c->addr;
	m.flags = rd ? I2C_M_RD : 0;
	m.len = (u16)len;
	m.buf = buf;
	return i2c_transfer(c->adapter, &m, 1);
}

static int elan_send(struct i2c_client *c, const u8 *buf, int len)
{
	return elan_xfer(c, (u8 *)buf, len, 0);
}

static int elan_recv(struct i2c_client *c, u8 *buf, int len)
{
	return elan_xfer(c, buf, len, 1);
}

/*
 * AXP227 @ 0x34 is already claimed by the MFD driver. Do not i2c_new_dummy
 * that address -- it fails and power stays off. Talk on the adapter instead
 * (same as userspace tp-io via /dev/i2c-0).
 */
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
		m[0].addr = ELAN_AXP_ADDR;
		m[0].flags = 0;
		m[0].len = 2;
		m[0].buf = wb;
		n = i2c_transfer(adap, m, 1);
		return n == 1 ? 0 : (n < 0 ? n : -EIO);
	}

	wb[0] = reg;
	m[0].addr = ELAN_AXP_ADDR;
	m[0].flags = 0;
	m[0].len = 1;
	m[0].buf = wb;
	m[1].addr = ELAN_AXP_ADDR;
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
	w = (u8)((v & ~7u) | AXP_LDOIO_FUNC_ON);
	return axp_rw(adap, ctl, &w, 1);
}

static int elan_power_on(void)
{
	struct i2c_adapter *adap;
	int i, r;

	for (i = 0; i < 40; i++) {
		adap = i2c_get_adapter(axp_bus);
		if (adap)
			break;
		msleep(100);
	}
	if (!adap) {
		pr_warn(ELAN_NAME ": no AXP adapter %d\n", axp_bus);
		return 0;
	}

	r = axp_ldo_on(adap, AXP_LDOIO0_CTL, AXP_LDOIO0_VOLT);
	if (r)
		pr_warn(ELAN_NAME ": ldoio0 %d\n", r);
	msleep(40);
	r = axp_ldo_on(adap, AXP_LDOIO1_CTL, AXP_LDOIO1_VOLT);
	if (r)
		pr_warn(ELAN_NAME ": ldoio1 %d\n", r);
	msleep(80);

	i2c_put_adapter(adap);
	return 0;
}

static void elan_reset_chip(void)
{
	int r;

	r = gpio_request(rst_gpio, "elankc1_rst");
	if (r && r != -EBUSY)
		pr_warn(ELAN_NAME ": rst gpio %d request %d\n", rst_gpio, r);
	gpio_direction_output(rst_gpio, 1);
	gpio_set_value(rst_gpio, 0);
	msleep(200);
	gpio_set_value(rst_gpio, 1);
	msleep(20);
}

static int is_hello(const u8 *b)
{
	return b[0] == 0x55 && b[1] == 0x55 &&
	       b[2] == 0x55 && b[3] == 0x55;
}

static int drain_hello(struct i2c_client *c)
{
	u8 buf[4];
	int i, r;

	for (i = 0; i < 12; i++) {
		memset(buf, 0xcc, 4);
		r = elan_recv(c, buf, 4);
		pr_info(ELAN_NAME
			": hello try %d xfer=%d %02x %02x %02x %02x\n",
			i, r, buf[0], buf[1], buf[2], buf[3]);
		if (r >= 0 && is_hello(buf))
			return 0;
		msleep(40);
	}
	return -ENODEV;
}

static unsigned scale_axis(unsigned v, unsigned lo, unsigned hi,
			   unsigned dst)
{
	unsigned maxp, span;

	if (dst == 0 || hi <= lo)
		return 0;
	maxp = dst - 1;
	if (v <= lo)
		return 0;
	if (v >= hi)
		return maxp;
	span = hi - lo;
	return (v - lo) * maxp / span;
}

static void map_xy(u16 rawx, u16 rawy, unsigned *ox, unsigned *oy)
{
	unsigned w = scr_w > 0 ? (unsigned)scr_w : SCR_W;
	unsigned h = scr_h > 0 ? (unsigned)scr_h : SCR_H;

	if (rot == 1) {
		*ox = scale_axis(rawy, RAW_Y0, RAW_Y1, w);
		*oy = h - 1 - scale_axis(rawx, RAW_X0, RAW_X1, h);
	} else if (rot == 2) {
		*ox = w - 1 - scale_axis(rawx, RAW_X0, RAW_X1, w);
		*oy = h - 1 - scale_axis(rawy, RAW_Y0, RAW_Y1, h);
	} else if (rot == 3) {
		*ox = w - 1 - scale_axis(rawy, RAW_Y0, RAW_Y1, w);
		*oy = scale_axis(rawx, RAW_X0, RAW_X1, h);
	} else {
		*ox = scale_axis(rawx, RAW_X0, RAW_X1, w);
		*oy = scale_axis(rawy, RAW_Y0, RAW_Y1, h);
	}
}

static void elan_report(struct elankc1 *ts, int down, u16 rawx, u16 rawy)
{
	unsigned x = 0, y = 0;

	if (down)
		map_xy(rawx, rawy, &x, &y);

	input_mt_slot(ts->input, 0);
	if (down) {
		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
		input_report_abs(ts->input, ABS_MT_POSITION_X, x);
		input_report_abs(ts->input, ABS_MT_POSITION_Y, y);
		input_report_abs(ts->input, ABS_X, x);
		input_report_abs(ts->input, ABS_Y, y);
		input_report_key(ts->input, BTN_TOUCH, 1);
	} else {
		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, false);
		input_report_key(ts->input, BTN_TOUCH, 0);
	}
	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
}

static int parse_mt(struct elankc1 *ts, const u8 *buf)
{
	unsigned i, state;
	u8 sum = 0;
	int any = 0;
	u16 x = 0, y = 0;

	if (buf[0] != 0x62)
		return 0;
	for (i = 0; i < 34; i++)
		sum += buf[i];
	if (sum != buf[34])
		return 0;

	state = ((buf[2] & 0x30) << 4) | buf[1];
	for (i = 0; i < 10; i++) {
		if (state & 1) {
			const u8 *p = buf + 3 + i * 3;

			x = ((p[0] & 0xf0) << 4) | p[1];
			y = ((p[0] & 0x0f) << 8) | p[2];
			any = 1;
			break;
		}
		state >>= 1;
	}

	if (any != ts->last_down ||
	    (any && (x != ts->last_x || y != ts->last_y))) {
		ts->last_down = any;
		ts->last_x = x;
		ts->last_y = y;
		elan_report(ts, any, x, y);
	} else if (!any && ts->last_down) {
		ts->last_down = 0;
		elan_report(ts, 0, 0, 0);
	}
	return 1;
}

static void elan_read_frame(struct elankc1 *ts)
{
	u8 buf[64];

	if (elan_recv(ts->client, buf, 55) < 0)
		return;
	if (buf[0] == 0x55 || buf[0] == 0x52 || buf[0] == 0x9b ||
	    buf[0] == 0xff)
		return;
	if (buf[0] == 0x62 && buf[2] >= 40 && buf[2] <= 55)
		parse_mt(ts, buf + 4);
	else if (buf[0] == 0x62)
		parse_mt(ts, buf);
}

static void elan_poll_work(struct work_struct *w)
{
	struct elankc1 *ts = container_of(w, struct elankc1, poll.work);

	elan_read_frame(ts);
	schedule_delayed_work(&ts->poll, msecs_to_jiffies(20));
}

static int elan_chip_start(struct elankc1 *ts)
{
	int r;

	r = drain_hello(ts->client);
	if (r) {
		elan_send(ts->client, cmd_rst, 4);
		msleep(80);
		elan_send(ts->client, cmd_main, 4);
		msleep(80);
		r = drain_hello(ts->client);
		if (r) {
			pr_err(ELAN_NAME ": no hello -- not hanging boot\n");
			return r;
		}
	}
	elan_send(ts->client, cmd_idle, 4);
	msleep(10);
	elan_send(ts->client, cmd_resume, 4);
	return 0;
}

static int elan_input_setup(struct elankc1 *ts)
{
	struct input_dev *idev;
	int r;

	idev = input_allocate_device();
	if (!idev)
		return -ENOMEM;

	idev->name = ELAN_INPUT_NAME;
	idev->phys = "i2c-" ELAN_NAME "/input0";
	idev->id.bustype = BUS_I2C;
	idev->id.vendor = 0x04f3;
	idev->id.product = 0x0010;
	idev->id.version = 1;
	idev->dev.parent = &ts->client->dev;

	__set_bit(EV_ABS, idev->evbit);
	__set_bit(EV_KEY, idev->evbit);
	__set_bit(BTN_TOUCH, idev->keybit);
	__set_bit(INPUT_PROP_DIRECT, idev->propbit);

	input_set_abs_params(idev, ABS_X, 0, scr_w - 1, 0, 0);
	input_set_abs_params(idev, ABS_Y, 0, scr_h - 1, 0, 0);
	r = input_mt_init_slots(idev, 10, INPUT_MT_DIRECT);
	if (r) {
		input_free_device(idev);
		return r;
	}
	input_set_abs_params(idev, ABS_MT_POSITION_X, 0, scr_w - 1, 0, 0);
	input_set_abs_params(idev, ABS_MT_POSITION_Y, 0, scr_h - 1, 0, 0);

	r = input_register_device(idev);
	if (r) {
		input_free_device(idev);
		return r;
	}
	ts->input = idev;
	return 0;
}

static int elan_poll_start(struct elankc1 *ts)
{
	int r;

	r = gpio_request(irq_gpio, "elankc1_irq");
	if (r && r != -EBUSY)
		pr_warn(ELAN_NAME ": irq gpio %d request %d\n", irq_gpio, r);
	gpio_direction_input(irq_gpio);
	pr_info(ELAN_NAME ": poll gpio %d val=%d\n",
		irq_gpio, gpio_get_value(irq_gpio));
	/*
	 * After hello/resume INT is often already low, so a falling-edge
	 * IRQ would never fire. Poll gpio47 like userspace elan-d.
	 */
	if (gpio_get_value(irq_gpio) == 0)
		elan_read_frame(ts);
	schedule_delayed_work(&ts->poll, msecs_to_jiffies(20));
	return 0;
}

static void elan_cleanup(struct elankc1 *ts)
{
	cancel_delayed_work_sync(&ts->poll);
	if (ts->input)
		input_unregister_device(ts->input);
	if (ts->client)
		i2c_unregister_device(ts->client);
	gpio_free(rst_gpio);
	gpio_free(irq_gpio);
}

static struct elankc1 *g_ts;

static int __init elankc1_init(void)
{
	struct i2c_adapter *adap;
	struct elankc1 *ts;
	int i, r;

	ts = kzalloc(sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;
	ts->last_down = -1;
	g_ts = ts;
	INIT_DELAYED_WORK(&ts->poll, elan_poll_work);

	pr_info(ELAN_NAME
		": ED078KC1 Elan @ i2c-%d 0x%02x rst=%d irq_gpio=%d\n",
		i2c_bus, i2c_addr, rst_gpio, irq_gpio);

	for (i = 0; i < 50; i++) {
		adap = i2c_get_adapter(i2c_bus);
		if (adap)
			break;
		msleep(100);
	}
	if (!adap) {
		pr_err(ELAN_NAME ": no i2c-%d (timeout, not hanging)\n",
		       i2c_bus);
		kfree(ts);
		g_ts = NULL;
		return -ENODEV;
	}

	ts->client = i2c_new_dummy(adap, i2c_addr);
	i2c_put_adapter(adap);
	if (!ts->client) {
		pr_err(ELAN_NAME ": i2c_new_dummy 0x%02x failed\n",
		       i2c_addr);
		kfree(ts);
		g_ts = NULL;
		return -ENODEV;
	}

	elan_power_on();
	elan_reset_chip();

	r = elan_chip_start(ts);
	if (r)
		goto fail;

	r = elan_input_setup(ts);
	if (r)
		goto fail;

	elan_poll_start(ts);
	pr_info(ELAN_NAME ": input \"%s\" %dx%d rot=%d\n",
		ELAN_INPUT_NAME, scr_w, scr_h, rot);
	return 0;

fail:
	elan_cleanup(ts);
	kfree(ts);
	g_ts = NULL;
	return r;
}

static void __exit elankc1_exit(void)
{
	if (!g_ts)
		return;
	elan_cleanup(g_ts);
	kfree(g_ts);
	g_ts = NULL;
}

module_init(elankc1_init);
module_exit(elankc1_exit);

MODULE_AUTHOR("PB740-2 ED078KC1 port");
MODULE_DESCRIPTION("Elan I2C touch (KC1) for PocketBook 740 Pro");
MODULE_LICENSE("GPL");
MODULE_ALIAS("i2c:elankc1");
