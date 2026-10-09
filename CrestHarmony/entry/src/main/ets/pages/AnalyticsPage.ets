import { localizedFormat } from '../core/Localization';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { exportCSV } from '../services/Export';
import { Session } from '../services/Session';
import { errorText } from '../services/Api';
import { Overview, Dimension, Metric, DateRange } from '../core/Models';
import { StoreScope, StoreOption, Product, Products, ProductTrend, Labor, LaborPoint, RevenueTrend, RevenueAlerts, RevenueAlert,
  ChartPoint, AnalyticsDetail, dimensionDetail, laborDetail, alertDetail, analyticsExportRows,
  periodQuery, recentTrend, storeOptions, validRange, numberText } from '../core/Analytics';
import { analyticsRange } from '../core/Dates';
import { Palette, IconButton, StateMessage } from '../components/Theme';
import { TrendChart } from '../components/TrendChart';

@Component
export struct AnalyticsPage {
  @StorageLink('locale') locale: string = 'zh-Hans';
  private t(key: string, args: string[] = []): string { return localizedFormat(key, this.locale, args); }
  @ObjectLink @Watch('workspaceChanged') session: Session;
  @StorageLink('dark') dark: boolean = true;
  @State module: number = 0; @State period: number = 2; @State range: DateRange = analyticsRange(2);
  @State storeKeys: string[] = []; @State stores: StoreOption[] = []; @State storeError: string = '';
  @State overview: Overview | undefined = undefined; @State revenue: RevenueTrend | undefined = undefined; @State products: Products | undefined = undefined; @State productTrend: ProductTrend | undefined = undefined;
  @State labor: Labor | undefined = undefined; @State alerts: RevenueAlerts | undefined = undefined; @State loading: boolean = false; @State error: string = ''; @State supplementalError: string = '';
  @State laborTrend: Labor | undefined = undefined; @State selectedDetail: AnalyticsDetail | undefined = undefined; @State pendingPeriod: number = -1;
  @State filter: boolean = false; @State sheet: boolean = false; @State dateFrom: string = ''; @State dateTo: string = ''; @State filterError: string = ''; @State pendingStores: string[] = [];
  @State detail: boolean = false; @State selectedProduct: Product | undefined = undefined; @State detailTrend: ProductTrend | undefined = undefined; @State detailError: string = ''; @State detailLoading: boolean = false;
  private epoch: number = 0; private detailEpoch: number = 0; private revision: number = -1; private alive: boolean = false;
  @State exporting: boolean = false;
  aboutToAppear(): void { this.alive = true; this.revision = this.session.revision; this.loadStores(); this.load(); }
  aboutToDisappear(): void { this.alive = false; this.epoch++; this.detailEpoch++; }
  private workspaceChanged(): void {
    if (this.revision === this.session.revision) return;
    this.revision = this.session.revision; this.storeKeys = []; this.stores = []; this.detail = false; this.sheet = false; this.detailEpoch++; this.loadStores(); this.load();
  }
  private async get<T>(path: string): Promise<T> { return this.session.authenticated((token: string) => this.session.api.call<T>(http.RequestMethod.GET, '/api/v1/analytics/' + path, '', token)); }
  private async loadStores(): Promise<void> {
    const revision = this.session.revision; this.storeError = '';
    if (!this.session.user?.tenant_id) return;
    try { const result = await this.get<StoreScope>('store-scope-tree'); if (this.alive && revision === this.session.revision) this.stores = storeOptions(result.nodes); }
    catch (error) { if (this.alive && revision === this.session.revision) this.storeError = errorText(error as Error); }
  }
  private async load(refresh: boolean = false): Promise<void> {
    const epoch = ++this.epoch; this.loading = true; this.error = ''; this.supplementalError = '';
    this.overview = undefined; this.revenue = undefined; this.products = undefined; this.productTrend = undefined; this.labor = undefined; this.laborTrend = undefined; this.alerts = undefined;
    if (!this.session.user?.tenant_id) { this.loading = false; return; }
    const query = periodQuery(this.range, this.storeKeys), trend = periodQuery(recentTrend(), this.storeKeys);
    try {
      if (this.module === 0 || this.module === 1) {
        const result = await this.get<Overview>(`operations/overview?${query}&compare=previous&granularity=day&order_breakdown=channel&refresh=${refresh}`);
        if (epoch !== this.epoch) return; this.overview = result;
        try {
          const chart = await this.get<RevenueTrend>(`trends/revenue?${trend}&store_key=ALL&source_type=all&granularity=day&include_current=false`);
          if (epoch === this.epoch) this.revenue = chart;
        } catch (error) { if (epoch === this.epoch) this.supplementalError = this.t('营收趋势：') + errorText(error as Error); }
      } else if (this.module === 2) {
        const result = await this.get<Products>(`operations/products?${query}&compare=previous&granularity=day&limit=30`);
        if (epoch !== this.epoch) return; this.products = result;
        try {
          const recent = await this.get<Products>(`operations/products?${trend}&compare=previous&granularity=day&limit=30`);
          if (epoch !== this.epoch) return;
          if (recent.items.length) { const chart = await this.get<ProductTrend>(this.productPath(recent.items[0].product_key, recentTrend())); if (epoch === this.epoch) this.productTrend = chart; }
        } catch (error) { if (epoch === this.epoch) this.supplementalError = this.t('产品趋势：') + errorText(error as Error); }
      } else if (this.module === 3) {
        const result = await this.get<Labor>(`operations/labor?${query}&compare=previous&granularity=day`);
        if (epoch !== this.epoch) return; this.labor = result;
        try {
          const chart = await this.get<Labor>(`operations/labor?${trend}&compare=previous&granularity=day`);
          if (epoch === this.epoch) this.laborTrend = chart;
        } catch (error) { if (epoch === this.epoch) this.supplementalError = errorText(error as Error); }
      } else {
        const result = await this.get<RevenueAlerts>(`revenue-alerts?business_date=${this.range.date_to}`); if (epoch === this.epoch) this.alerts = result;
      }
    } catch (error) { if (epoch === this.epoch) this.error = errorText(error as Error); }
    finally { if (epoch === this.epoch) this.loading = false; }
  }
  private productPath(key: string, range: DateRange): string {
    return `products/trend?${periodQuery(range, this.storeKeys)}&product_key=${encodeURIComponent(key)}&dim_key=${encodeURIComponent(this.storeKeys.length === 1 ? this.storeKeys[0] : 'ALL')}&dim_type=${this.storeKeys.length === 1 ? 'shop' : 'all'}&granularity=day&include_current=false`;
  }
  private async openProduct(product: Product): Promise<void> {
    const epoch = ++this.detailEpoch; this.selectedDetail = undefined; this.selectedProduct = product; this.detail = true; this.filter = false; this.sheet = true; this.detailLoading = true; this.detailTrend = undefined; this.detailError = '';
    try { const result = await this.get<ProductTrend>(this.productPath(product.product_key, this.range)); if (epoch === this.detailEpoch) this.detailTrend = result; }
    catch (error) { if (epoch === this.detailEpoch) this.detailError = errorText(error as Error); }
    finally { if (epoch === this.detailEpoch) this.detailLoading = false; }
  }
  private setPeriod(index: number): void { this.period = index; this.range = analyticsRange(index); this.load(); }
  private openDetail(value: AnalyticsDetail): void {
    this.detailEpoch++; this.selectedDetail = value; this.selectedProduct = undefined; this.detail = true; this.filter = false; this.sheet = true;
  }
  private async exportData(): Promise<void> {
    if (this.exporting) return;
    if (!(this.overview || this.products || this.labor || this.alerts)) return;
    const rows = analyticsExportRows(['经营总览', '订单解析', '产品分析', '人效分析', '营收报警'][this.module], this.range,
      this.storeKeys.length ? this.stores.filter((store: StoreOption) => this.storeKeys.includes(store.key)).map((store: StoreOption) => store.label).join('、') : '全部门店',
      { overview: this.overview, products: this.products, labor: this.labor, alerts: this.alerts ? this.visibleAlerts() : undefined });
    this.exporting = true;
    try {
      const saved = await exportCSV(getContext(this) as common.UIAbilityContext, `Crest-${this.range.date_from}-${this.range.date_to}`, rows);
      if (saved && this.alive) this.getUIContext().getPromptAction().showToast({ message: this.t('已导出 CSV') });
    } catch (error) { if (this.alive) this.getUIContext().getPromptAction().showToast({ message: errorText(error as Error) }); }
    finally { this.exporting = false; }
  }
  private showFilter(): void { this.dateFrom = this.range.date_from; this.dateTo = this.range.date_to; this.pendingPeriod = this.period; this.pendingStores = this.storeKeys.slice(); this.filterError = ''; this.filter = true; this.detail = false; this.sheet = true; }
  private chooseDate(start: boolean): void {
    const date = (start ? this.dateFrom : this.dateTo).split('-').map((value: string) => Number(value));
    const latest = analyticsRange(0).date_to.split('-').map((value: string) => Number(value));
    DatePickerDialog.show({ start: new Date(1970, 0, 1), end: new Date(latest[0], latest[1] - 1, latest[2]),
      selected: new Date(date[0], date[1] - 1, date[2]), lunar: false,
      onDateAccept: (value: Date) => {
        const text = `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`;
        if (start) this.dateFrom = text; else this.dateTo = text;
        this.pendingPeriod = -1;
      } });
  }
  @Builder private section(title: string) { Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).alignSelf(ItemAlign.Start) }
  @Builder private metric(label: string, value: string, comparison: string = '') {
    Column({ space: 8 }) {
      Text(label).fontSize(13).fontColor(Palette.secondary(this.dark))
      Text(value).fontFamily('CrestRounded').fontSize(24).fontColor(Palette.text(this.dark))
      if (comparison) { Text(comparison).fontSize(12).fontColor(Palette.secondary(this.dark)) }
    }.alignItems(HorizontalAlign.Start).padding(18).width('100%').backgroundColor(Palette.field(this.dark)).borderRadius(20)
  }
  private comparison(metric?: Metric): string {
    return metric?.change_rate === undefined || metric.change_rate === null ? this.t('上期无可比数据') : this.t('较上期 %@', [`${metric.change_rate >= 0 ? '+' : ''}${(metric.change_rate * 100).toFixed(1)}%`]);
  }
  @Builder private dimensions(title: string, items: Dimension[]) {
    this.section(title)
    if (!items.length) { Text(this.t('暂无数据')).fontColor(Palette.secondary(this.dark)).fontSize(14) }
    ForEach(items, (item: Dimension) => {
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text(item.dim_label || item.store_label || item.dim_key || item.store_key || '—').fontSize(15).fontColor(Palette.text(this.dark))
          Text(this.t('%@ 单', [numberText(item.metrics['order_count']?.current)])).fontSize(12).fontColor(Palette.secondary(this.dark))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(numberText(item.metrics['net_income']?.current, true)).fontFamily('CrestRounded').fontSize(19).fontColor(Palette.text(this.dark))
      }.padding(16).width('100%').backgroundColor(Palette.field(this.dark)).borderRadius(16).onClick(() => this.openDetail(dimensionDetail(item, title)))
    })
  }
  @Builder private overviewContent(value: Overview) {
    this.metric(this.t('实收金额'), numberText(value.metrics['net_income']?.current, true), this.comparison(value.metrics['net_income']))
    this.metric(this.t('订单数'), numberText(value.metrics['order_count']?.current), this.comparison(value.metrics['order_count']))
    this.metric(this.t('客单价'), numberText(value.metrics['avg_order_value']?.current, true), this.comparison(value.metrics['avg_order_value']))
    if (this.revenue?.points.length) {
      this.section(this.module === 1 ? this.t('近 30 天订单趋势') : this.t('近 30 天营收趋势'))
      TrendChart({ points: this.revenue.points.map((point): ChartPoint => ({ label: point.period, value: point.missing ? undefined : this.module === 1 ? point.order_count : point.net_income })) })
    }
    this.dimensions(this.t('渠道分布'), value.channels || [])
    this.dimensions(this.t('门店表现'), value.stores || [])
  }
  @Builder private productsContent(value: Products) {
    if (value.data_status !== 'ok' && value.data_status !== 'complete') { Text(this.t('数据状态：%@', [value.data_status])).fontSize(12).fontColor(Palette.secondary(this.dark)) }
    if (this.productTrend?.points.length) {
      this.section(this.t('近 30 天 · %@', [this.productTrend.product_name || this.t('热门产品')]))
      TrendChart({ points: this.productTrend.points.map((point): ChartPoint => ({ label: point.period, value: point.missing ? undefined : point.sales_amount })) })
    }
    this.section(this.t('产品排行'))
    if (!value.items.length) { StateMessage({ title: this.t('暂无产品数据') }) }
    ForEach(value.items, (product: Product, index: number) => {
      Row({ space: 12 }) {
        Text(`${index + 1}`).fontSize(18).fontFamily('CrestRounded').fontColor(Palette.secondary(this.dark)).width(28)
        Column({ space: 6 }) {
          Text(product.product_name).fontSize(16).fontColor(Palette.text(this.dark))
          Text(this.t('销量 %@ · 金额占比 %@%%', [numberText(product.quantity), (product.amount_share * 100).toFixed(1)])).fontSize(12).fontColor(Palette.secondary(this.dark))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(numberText(product.sales_amount, true)).fontFamily('CrestRounded').fontSize(18).fontColor(Palette.text(this.dark))
      }.padding(16).backgroundColor(Palette.field(this.dark)).borderRadius(16).onClick(() => this.openProduct(product))
    }, (product: Product) => product.product_key)
    Text(this.t('展示前 %@ 项，共 %@ 项', [String(value.items.length), String(value.total)])).fontSize(12).fontColor(Palette.secondary(this.dark))
  }
  @Builder private laborContent(value: Labor) {
    if (!value.points.length) { StateMessage({ title: this.t('暂无人效数据') }) }
    this.metric(this.t('实际工时'), numberText(value.summary.actual_hours) + this.t(' 小时'))
    this.metric(this.t('计划工时'), numberText(value.summary.planned_hours) + this.t(' 小时'))
    this.metric(this.t('实际人效'), numberText(value.summary.actual_revenue_per_hour, true) + this.t(' / 小时'))
    this.metric(this.t('人数'), numberText(value.summary.headcount))
    this.section(this.t('小时产出趋势'))
    TrendChart({ points: (this.laborTrend?.points || []).map((point: LaborPoint): ChartPoint => ({ label: point.period,
      value: point.data_status === 'missing' ? undefined : point.actual_revenue_per_hour, comparison: point.data_status === 'missing' ? undefined : point.planned_revenue_per_hour })), comparisonLabel: this.t('计划') })
    this.section(this.t('工时趋势'))
    TrendChart({ points: (this.laborTrend?.points || []).map((point: LaborPoint): ChartPoint => ({ label: point.period,
      value: point.data_status === 'missing' ? undefined : point.actual_hours, comparison: point.data_status === 'missing' ? undefined : point.planned_hours })), comparisonLabel: this.t('计划') })
    this.section(this.t('每日明细'))
    ForEach(value.points, (point: LaborPoint) => {
      Row() {
        Text(point.period).fontColor(Palette.text(this.dark)).layoutWeight(1)
        Text(numberText(point.actual_revenue_per_hour, true)).fontColor(Palette.secondary(this.dark))
      }.padding(16).width('100%').borderRadius(16).backgroundColor(Palette.surface(this.dark)).onClick(() => this.openDetail(laborDetail(point)))
    })
    Text(this.t('数据状态：%@', [value.data_status])).fontSize(12).fontColor(Palette.secondary(this.dark))
  }
  private visibleAlerts(): RevenueAlert[] { return (this.alerts?.alerts || []).filter((item: RevenueAlert) => !this.storeKeys.length || this.storeKeys.includes(item.shop_key)); }
  @Builder private alertsContent() {
    Text(this.t('业务日期：%@', [this.range.date_to])).fontSize(13).fontColor(Palette.secondary(this.dark))
    if (!this.visibleAlerts().length) { StateMessage({ title: this.t('暂无营收报警'), detail: this.t('当前日期和门店范围内没有报警记录') }) }
    ForEach(this.visibleAlerts(), (item: RevenueAlert) => {
      Column({ space: 10 }) {
        Text(item.shop_label || item.shop_key).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark))
        Text(this.t('实际 %@ · 基线 %@', [numberText(item.actual_amount, true), numberText(item.baseline_amount, true)])).fontSize(14).fontColor(Palette.text(this.dark))
        Text(this.t('偏差 %@%% · %@', [item.deviation_pct.toFixed(1), item.status])).fontSize(13).fontColor(Palette.error(this.dark))
        ForEach(item.reason_hints || [], (reason: string) => { Text(reason).fontSize(13).fontColor(Palette.secondary(this.dark)) })
      }.alignItems(HorizontalAlign.Start).width('100%').padding(18).borderRadius(20).backgroundColor(Palette.field(this.dark)).onClick(() => this.openDetail(alertDetail(item)))
    })
  }
  @Builder private filterContent() {
    Column({ space: 18 }) {
      Text(this.t('日期与门店')).fontSize(21).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark))
      Row({ space: 6 }) {
        ForEach(['昨日', '近 7 天', '本月', '上月'], (name: string, index: number) => {
          Button(this.t(name)).fontSize(13).layoutWeight(1).fontColor(this.pendingPeriod === index ? Color.White : Palette.text(this.dark))
            .backgroundColor(this.pendingPeriod === index ? Palette.accent(this.dark) : Palette.surface(this.dark)).onClick(() => {
              const range = analyticsRange(index); this.pendingPeriod = index; this.dateFrom = range.date_from; this.dateTo = range.date_to;
            })
        })
      }
      Row({ space: 10 }) {
        Button(this.dateFrom).layoutWeight(1).fontSize(14).fontColor(Palette.text(this.dark)).backgroundColor(Palette.surface(this.dark)).onClick(() => this.chooseDate(true))
        Text(this.t('至')).fontColor(Palette.secondary(this.dark))
        Button(this.dateTo).layoutWeight(1).fontSize(14).fontColor(Palette.text(this.dark)).backgroundColor(Palette.surface(this.dark)).onClick(() => this.chooseDate(false))
      }
      Button(this.t('全部门店')).fontColor(Palette.text(this.dark)).backgroundColor(Palette.field(this.dark)).onClick(() => this.pendingStores = [])
      if (this.storeError) { StateMessage({ title: this.t('门店范围加载失败'), detail: this.storeError, action: this.t('重试'), onAction: () => this.loadStores() }) }
      List({ space: 4 }) {
        ForEach(this.stores, (store: StoreOption) => {
          ListItem() {
            Row() {
              Text(store.label).fontSize(16).fontColor(Palette.text(this.dark)).layoutWeight(1)
              Checkbox().select(this.pendingStores.includes(store.key)).onChange((checked: boolean) => { this.pendingStores = checked ? this.pendingStores.concat([store.key]) : this.pendingStores.filter((key: string) => key !== store.key); })
            }.padding(12)
          }
        }, (store: StoreOption) => store.key)
      }.layoutWeight(1)
      if (this.filterError) { Text(this.filterError).fontColor(Palette.error(this.dark)).fontSize(13) }
      Button(this.t('应用筛选')).width('100%').onClick(() => {
        if (!validRange(this.dateFrom, this.dateTo)) { this.filterError = this.t('开始日期不能晚于结束日期，结束日期不能晚于昨日'); return; }
        this.range = { date_from: this.dateFrom, date_to: this.dateTo }; this.storeKeys = this.pendingStores; this.period = this.pendingPeriod; this.sheet = false; this.load();
      })
    }.padding(24).width('100%').height('100%').backgroundColor(Palette.glass(this.dark)).backgroundBlurStyle(BlurStyle.Thick)
  }
  @Builder private productDetail() {
    Scroll() {
      Column({ space: 18 }) {
        this.section(this.selectedProduct?.product_name || this.t('产品详情'))
        this.metric(this.t('销售额'), numberText(this.selectedProduct?.sales_amount, true))
        this.metric(this.t('销量'), numberText(this.selectedProduct?.quantity))
        this.metric(this.t('订单数'), numberText(this.selectedProduct?.order_count))
        this.metric(this.t('销售额占比'), this.selectedProduct ? (this.selectedProduct.amount_share * 100).toFixed(1) + '%' : '—')
        this.metric(this.t('数量占比'), this.selectedProduct ? (this.selectedProduct.quantity_share * 100).toFixed(1) + '%' : '—')
        if (this.detailLoading) { StateMessage({ title: this.t('正在加载趋势'), busy: true }) }
        else if (this.detailError) { StateMessage({ title: this.t('趋势加载失败'), detail: this.detailError, action: this.t('重试'), onAction: () => { if (this.selectedProduct) this.openProduct(this.selectedProduct); } }) }
        else if (this.detailTrend?.points.length) { TrendChart({ points: this.detailTrend.points.map((point): ChartPoint => ({ label: point.period, value: point.missing ? undefined : point.sales_amount })) }) }
        else { StateMessage({ title: this.t('暂无趋势数据') }) }
      }.padding(24).width('100%')
    }.width('100%').height('100%').backgroundColor(Palette.glass(this.dark)).backgroundBlurStyle(BlurStyle.Thick)
  }
  @Builder private sheetContent() {
    if (this.filter) { this.filterContent() }
    else if (this.selectedDetail) {
      Column({ space: 16 }) {
        Row() {
          Text(this.selectedDetail.title).fontSize(20).fontWeight(FontWeight.Medium).fontColor(Palette.text(this.dark)).layoutWeight(1)
          IconButton({ kind: 'close', label: this.t('关闭详情'), action: () => this.sheet = false })
        }.width('100%')
        Text(this.t(this.selectedDetail.subtitle)).fontSize(13).fontColor(Palette.secondary(this.dark))
        Scroll() {
          Column() {
            ForEach(this.selectedDetail.rows, (row: string[]) => {
              Row({ space: 16 }) {
                Text(this.t(row[0])).fontSize(15).fontColor(Palette.secondary(this.dark)).layoutWeight(1)
                Text(row[1]).fontSize(15).fontColor(Palette.text(this.dark)).textAlign(TextAlign.End).layoutWeight(1)
              }.padding(16).width('100%').border({ width: { bottom: .5 }, color: Palette.border(this.dark) })
            })
          }.backgroundColor(Palette.surface(this.dark)).borderRadius(20).width('100%')
        }.layoutWeight(1)
      }.padding(24).width('100%').height('100%')
    } else { this.productDetail() }
  }
  build() {
    Column({ space: 12 }) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach([this.t('经营概览'), this.t('订单分析'), this.t('产品分析'), this.t('人效分析'), this.t('营收报警')], (name: string, index: number) => {
            Button(name).fontSize(14).backgroundColor(index === this.module ? Palette.text(this.dark) : Palette.field(this.dark))
              .fontColor(index === this.module ? Palette.background(this.dark) : Palette.text(this.dark)).height(38)
              .onClick(() => { if (this.module !== index) { this.module = index; this.load(); } })
          })
        }.padding({ left: 20, right: 20 })
      }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Off)
      Row() {
        Select([{ value: this.t('昨日') }, { value: this.t('近 7 天') }, { value: this.t('本月') }, { value: this.t('上月') }]).selected(this.period).value(this.period < 0 ? this.t('自定义日期') : [this.t('昨日'), this.t('近 7 天'), this.t('本月'), this.t('上月')][this.period]).onSelect((index: number) => this.setPeriod(index))
        Blank()
        Button(this.storeKeys.length ? this.t('%@ 家门店', [String(this.storeKeys.length)]) : this.t('全部门店')).fontSize(13).backgroundColor(Palette.field(this.dark)).fontColor(Palette.text(this.dark)).onClick(() => this.showFilter())
        IconButton({ kind: 'retry', label: this.t('刷新经营分析'), glass: false, isEnabled: !this.loading, action: () => this.load(true) })
      }.padding({ left: 20, right: 14 }).width('100%')
      Row() {
        Text(`${this.range.date_from} — ${this.range.date_to}`).fontSize(12).fontColor(Palette.secondary(this.dark)).layoutWeight(1)
        Button(this.t('导出 CSV')).fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor(Palette.accent(this.dark))
          .enabled(!this.loading && !this.exporting && !!(this.overview || this.products || this.labor || this.alerts)).onClick(() => this.exportData())
      }.padding({ left: 20, right: 20 })
      if (!this.session.user?.tenant_id) { StateMessage({ title: this.t('企业工作空间专属'), detail: this.t('请加入团队或切换企业工作空间') }).layoutWeight(1) }
      else if (this.error) { StateMessage({ title: this.t('经营分析加载失败'), detail: this.error, action: this.t('重试'), onAction: () => this.load() }).layoutWeight(1) }
      else {
        Scroll() {
          Column({ space: 16 }) {
            if (this.loading) { LoadingProgress().width(30).height(30) }
            if (this.overview) { this.overviewContent(this.overview) }
            else if (this.products) { this.productsContent(this.products) }
            else if (this.labor) { this.laborContent(this.labor) }
            else if (this.alerts) { this.alertsContent() }
            if (this.supplementalError) { StateMessage({ title: this.t('部分数据未加载'), detail: this.supplementalError, action: this.t('重试'), onAction: () => this.load() }) }
          }.padding(20).width('100%')
        }.layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%')
      .bindSheet($$this.sheet, this.sheetContent, { height: '85%', backgroundColor: Palette.surface(this.dark), onDisappear: () => { this.detailEpoch++; } })
  }
}
