<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import {
  useAudienceFilterContext,
  valuesToRowValues,
  rowValuesToValues,
} from './audienceProvider';

const props = defineProps({
  modelValue: { type: Object, default: null },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();
const { filterTypes } = useAudienceFilterContext();

const DEFAULT_ROW = () => ({
  attributeKey: 'name',
  filterOperator: 'equal_to',
  values: '',
});

const rootCombinator = ref('and');
const entries = ref([{ kind: 'leaf', row: DEFAULT_ROW() }]);

const filterFor = attributeKey =>
  filterTypes.value.find(filter => filter.attributeKey === attributeKey);

const rowFromLeaf = leaf => ({
  attributeKey: leaf.attribute_key || 'name',
  filterOperator: leaf.filter_operator || 'equal_to',
  values: valuesToRowValues(leaf.values, filterFor(leaf.attribute_key)),
});

const initFromTree = tree => {
  if (!tree || !Array.isArray(tree.conditions) || !tree.conditions.length) {
    rootCombinator.value = 'and';
    entries.value = [{ kind: 'leaf', row: DEFAULT_ROW() }];
    return;
  }
  rootCombinator.value = tree.combinator === 'or' ? 'or' : 'and';
  entries.value = tree.conditions.map(condition => {
    if (Array.isArray(condition.conditions)) {
      return {
        kind: 'group',
        combinator: condition.combinator === 'or' ? 'or' : 'and',
        rows: condition.conditions.map(rowFromLeaf),
      };
    }
    return { kind: 'leaf', row: rowFromLeaf(condition) };
  });
};

const leafFromRow = row => ({
  attribute_key: row.attributeKey,
  filter_operator: row.filterOperator,
  values: rowValuesToValues(row.values),
});

const buildTree = () => ({
  combinator: rootCombinator.value,
  conditions: entries.value.map(entry =>
    entry.kind === 'group'
      ? {
          combinator: entry.combinator,
          conditions: entry.rows.map(leafFromRow),
        }
      : leafFromRow(entry.row)
  ),
});

const leafCount = computed(() =>
  entries.value.reduce(
    (count, entry) => count + (entry.kind === 'group' ? entry.rows.length : 1),
    0
  )
);

watch(
  [rootCombinator, entries],
  () => {
    emit('update:modelValue', buildTree());
  },
  { deep: true }
);

const addLeaf = () => {
  entries.value.push({ kind: 'leaf', row: DEFAULT_ROW() });
};

const addGroup = () => {
  entries.value.push({
    kind: 'group',
    combinator: rootCombinator.value === 'and' ? 'or' : 'and',
    rows: [DEFAULT_ROW()],
  });
};

const removeEntry = index => {
  entries.value.splice(index, 1);
};

const addGroupRow = group => {
  group.rows.push(DEFAULT_ROW());
};

const removeGroupRow = (group, index) => {
  group.rows.splice(index, 1);
};

onMounted(() => {
  initFromTree(props.modelValue);
  // The audience builder reuses the contact filter primitives, which need the
  // account's custom attribute definitions and labels in the store.
  store.dispatch('attributes/get').catch(() => {});
  store.dispatch('labels/get').catch(() => {});
});

watch(
  () => props.modelValue,
  tree => {
    if (tree === null) initFromTree(null);
  }
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-center gap-2">
      <label
        for="audience-root-combinator"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ t('PILOT.SETTINGS.AUDIENCE.MATCH_LABEL') }}
      </label>
      <select
        id="audience-root-combinator"
        v-model="rootCombinator"
        class="h-8 px-2 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9"
      >
        <option value="and">
          {{ t('PILOT.SETTINGS.AUDIENCE.COMBINATOR.ALL') }}
        </option>
        <option value="or">
          {{ t('PILOT.SETTINGS.AUDIENCE.COMBINATOR.ANY') }}
        </option>
      </select>
    </div>

    <ul class="grid gap-3 list-none">
      <li
        v-for="(entry, index) in entries"
        :key="`audience-entry-${index}`"
        class="list-none"
      >
        <ConditionRow
          v-if="entry.kind === 'leaf'"
          v-model:attribute-key="entry.row.attributeKey"
          v-model:filter-operator="entry.row.filterOperator"
          v-model:values="entry.row.values"
          :filter-types="filterTypes"
          @remove="removeEntry(index)"
        />
        <div
          v-else
          class="flex flex-col gap-3 p-3 rounded-lg border border-n-weak bg-n-alpha-1"
        >
          <div class="flex items-center justify-between gap-2">
            <select
              v-model="entry.combinator"
              class="h-8 px-2 rounded-lg border border-n-container bg-n-solid-1 text-sm text-n-slate-12 focus:outline-none focus:border-n-blue-9"
            >
              <option value="and">
                {{ t('PILOT.SETTINGS.AUDIENCE.COMBINATOR.ALL') }}
              </option>
              <option value="or">
                {{ t('PILOT.SETTINGS.AUDIENCE.COMBINATOR.ANY') }}
              </option>
            </select>
            <Button
              sm
              ghost
              slate
              icon="i-lucide-trash"
              @click="removeEntry(index)"
            />
          </div>
          <ul class="grid gap-3 list-none">
            <li
              v-for="(row, rowIndex) in entry.rows"
              :key="`audience-group-${index}-row-${rowIndex}`"
              class="list-none"
            >
              <ConditionRow
                v-model:attribute-key="row.attributeKey"
                v-model:filter-operator="row.filterOperator"
                v-model:values="row.values"
                :filter-types="filterTypes"
                @remove="removeGroupRow(entry, rowIndex)"
              />
            </li>
          </ul>
          <div>
            <Button sm ghost blue @click="addGroupRow(entry)">
              {{ t('PILOT.SETTINGS.AUDIENCE.ADD_CONDITION') }}
            </Button>
          </div>
        </div>
      </li>
    </ul>

    <div class="flex gap-2">
      <Button sm ghost blue @click="addLeaf">
        {{ t('PILOT.SETTINGS.AUDIENCE.ADD_CONDITION') }}
      </Button>
      <Button sm ghost slate @click="addGroup">
        {{ t('PILOT.SETTINGS.AUDIENCE.ADD_GROUP') }}
      </Button>
    </div>
    <p v-if="leafCount === 0" class="text-sm text-n-ruby-11" role="alert">
      {{ t('PILOT.SETTINGS.AUDIENCE.EMPTY_ERROR') }}
    </p>
  </div>
</template>
