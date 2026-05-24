<script>
import { mapGetters } from 'vuex';
import { useAlert, useTrack } from 'dashboard/composables';
import CsatMetrics from './components/CsatMetrics.vue';
import CsatTable from './components/CsatTable.vue';
import CsatFilters from './components/Csat/CsatFilters.vue';
import PilotSentimentCard from './components/PilotSentimentCard.vue';
import PilotThemesCard from './components/PilotThemesCard.vue';
import { generateFileName } from '../../../../helper/downloadHelper';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import V4Button from 'dashboard/components-next/button/Button.vue';
import ReportHeader from './components/ReportHeader.vue';

export default {
  name: 'CsatResponses',
  components: {
    CsatMetrics,
    CsatTable,
    CsatFilters,
    PilotSentimentCard,
    PilotThemesCard,
    ReportHeader,
    V4Button,
  },
  data() {
    return {
      pageIndex: 0,
      from: 0,
      to: 0,
      userIds: [],
      inbox: null,
      team: null,
      rating: null,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledOnAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    requestPayload() {
      return {
        from: this.from,
        to: this.to,
        user_ids: this.userIds,
        inbox_id: this.inbox,
        team_id: this.team,
        rating: this.rating,
      };
    },
    isTeamsEnabled() {
      return this.isFeatureEnabledOnAccount(
        this.accountId,
        FEATURE_FLAGS.TEAM_MANAGEMENT
      );
    },
    isPilotCsatAnalysisEnabled() {
      return (
        this.isFeatureEnabledOnAccount(
          this.accountId,
          FEATURE_FLAGS.PILOT_MASTER
        ) &&
        this.isFeatureEnabledOnAccount(
          this.accountId,
          FEATURE_FLAGS.PILOT_CSAT_ANALYSIS
        )
      );
    },
  },
  mounted() {
    this.$store.dispatch('agents/get');
  },
  methods: {
    getAllData() {
      try {
        this.$store.dispatch('csat/getMetrics', this.requestPayload);
        this.getResponses();
      } catch {
        useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
      }
    },
    getResponses() {
      this.$store.dispatch('csat/get', {
        page: this.pageIndex + 1,
        ...this.requestPayload,
      });
    },
    downloadReports() {
      const type = 'csat';
      try {
        this.$store.dispatch('csat/downloadCSATReports', {
          fileName: generateFileName({ type, to: this.to }),
          ...this.requestPayload,
        });
      } catch (error) {
        useAlert(this.$t('REPORT.CSAT_REPORTS.DOWNLOAD_FAILED'));
      }
    },
    onPageNumberChange(pageIndex) {
      this.pageIndex = pageIndex;
      this.getResponses();
    },
    onFilterChange({
      from,
      to,
      selectedAgents,
      selectedInbox,
      selectedTeam,
      selectedRating,
    }) {
      // do not track filter change on initial load
      if (this.from !== 0 && this.to !== 0) {
        useTrack(REPORTS_EVENTS.FILTER_REPORT, {
          filterType: 'date',
          reportType: 'csat',
        });
      }

      this.from = from;
      this.to = to;
      this.userIds = selectedAgents.map(el => el.id);
      this.inbox = selectedInbox?.id;
      this.team = selectedTeam?.id;
      this.rating = selectedRating?.value;

      this.getAllData();
    },
  },
};
</script>

<template>
  <ReportHeader :header-title="$t('CSAT_REPORTS.HEADER')">
    <V4Button
      :label="$t('CSAT_REPORTS.DOWNLOAD')"
      icon="i-ph-download-simple"
      size="sm"
      @click="downloadReports"
    />
  </ReportHeader>

  <div class="flex flex-col gap-6">
    <CsatFilters
      :show-team-filter="isTeamsEnabled"
      @filter-change="onFilterChange"
    />
    <CsatMetrics :filters="requestPayload" />
    <template v-if="isPilotCsatAnalysisEnabled">
      <div class="flex flex-col gap-6 lg:flex-row">
        <div class="flex-1">
          <PilotSentimentCard />
        </div>
        <div class="flex-1">
          <PilotThemesCard />
        </div>
      </div>
    </template>
    <CsatTable :page-index="pageIndex" @page-change="onPageNumberChange" />
  </div>
</template>
