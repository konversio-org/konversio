import { computed, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { useContactFilterContext } from 'dashboard/components-next/filter/contactProvider.js';

/**
 * Audience attribute set for the Pilot assistant audience builder: the core
 * contact filter attributes plus widget identity verification and the
 * conversation additional attributes the audience matcher can resolve.
 */
export function useAudienceFilterContext() {
  const { t } = useI18n();
  const { filterTypes: contactFilterTypes } = useContactFilterContext();

  const extraFilterTypes = computed(() => [
    {
      attributeKey: 'identity_verified',
      value: 'identity_verified',
      attributeName: t('PILOT.SETTINGS.AUDIENCE.ATTRIBUTES.IDENTITY_VERIFIED'),
      label: t('PILOT.SETTINGS.AUDIENCE.ATTRIBUTES.IDENTITY_VERIFIED'),
      inputType: 'booleanSelect',
      dataType: 'text',
      filterOperators: [
        {
          value: 'equal_to',
          label: t('FILTER.OPERATOR_LABELS.equal_to'),
          hasInput: true,
          icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
        },
        {
          value: 'not_equal_to',
          label: t('FILTER.OPERATOR_LABELS.not_equal_to'),
          hasInput: true,
          icon: h('span', { class: 'i-ph-not-equals-bold !text-n-blue-11' }),
        },
      ],
      attributeModel: 'standard',
    },
    {
      attributeKey: 'browser_language',
      value: 'browser_language',
      attributeName: t('PILOT.SETTINGS.AUDIENCE.ATTRIBUTES.BROWSER_LANGUAGE'),
      label: t('PILOT.SETTINGS.AUDIENCE.ATTRIBUTES.BROWSER_LANGUAGE'),
      inputType: 'plainText',
      dataType: 'text',
      filterOperators: [
        {
          value: 'equal_to',
          label: t('FILTER.OPERATOR_LABELS.equal_to'),
          hasInput: true,
          icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
        },
        {
          value: 'not_equal_to',
          label: t('FILTER.OPERATOR_LABELS.not_equal_to'),
          hasInput: true,
          icon: h('span', { class: 'i-ph-not-equals-bold !text-n-blue-11' }),
        },
      ],
      attributeModel: 'additional',
    },
    {
      attributeKey: 'conversation_language',
      value: 'conversation_language',
      attributeName: t(
        'PILOT.SETTINGS.AUDIENCE.ATTRIBUTES.CONVERSATION_LANGUAGE'
      ),
      label: t('PILOT.SETTINGS.AUDIENCE.ATTRIBUTES.CONVERSATION_LANGUAGE'),
      inputType: 'plainText',
      dataType: 'text',
      filterOperators: [
        {
          value: 'equal_to',
          label: t('FILTER.OPERATOR_LABELS.equal_to'),
          hasInput: true,
          icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
        },
        {
          value: 'not_equal_to',
          label: t('FILTER.OPERATOR_LABELS.not_equal_to'),
          hasInput: true,
          icon: h('span', { class: 'i-ph-not-equals-bold !text-n-blue-11' }),
        },
      ],
      attributeModel: 'additional',
    },
  ]);

  const filterTypes = computed(() => [
    ...contactFilterTypes.value,
    ...extraFilterTypes.value,
  ]);

  return { filterTypes };
}

const OBJECT_INPUT_TYPES = [
  'searchSelect',
  'asyncSearchSelect',
  'booleanSelect',
];
const ARRAY_INPUT_TYPES = ['multiSelect', 'multiText'];

const findOption = (filter, value) => {
  const option = filter?.options?.find(
    item => String(item.id) === String(value)
  );
  return option || { id: value, name: value };
};

/**
 * Converts a stored leaf `values` array into the shape ConditionRow expects
 * for the attribute's input type.
 */
export const valuesToRowValues = (values, filter) => {
  const stored = Array.isArray(values) ? values : [];
  const inputType = filter?.inputType;
  if (ARRAY_INPUT_TYPES.includes(inputType)) return [...stored];
  if (OBJECT_INPUT_TYPES.includes(inputType)) {
    return stored.length ? findOption(filter, stored[0]) : {};
  }
  return stored.length ? stored[0] : '';
};

/**
 * Converts a ConditionRow `values` model back into the stored leaf `values`
 * array.
 */
export const rowValuesToValues = rowValues => {
  if (Array.isArray(rowValues)) {
    return rowValues
      .filter(item => item !== '' && item != null)
      .map(item =>
        typeof item === 'object' && item !== null ? item.id : item
      );
  }
  if (rowValues && typeof rowValues === 'object') {
    return rowValues.id != null && rowValues.id !== '' ? [rowValues.id] : [];
  }
  return rowValues === '' || rowValues == null ? [] : [rowValues];
};
