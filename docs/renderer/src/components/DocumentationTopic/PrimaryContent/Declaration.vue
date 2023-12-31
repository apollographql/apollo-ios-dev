<!--
  This source file is part of the Swift.org open source project

  Copyright (c) 2021 Apple Inc. and the Swift project authors
  Licensed under Apache License v2.0 with Runtime Library Exception

  See https://swift.org/LICENSE.txt for license information
  See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

<template>
  <OnThisPageSection
    anchor="declaration"
    class="declaration"
    title="Declaration"
  >
    <h2>Declaration</h2>
    <template v-if="hasModifiedChanges">
      <DeclarationDiff
        :class="[changeClasses, multipleLinesClass]"
        :changes="declarationChanges"
        :changeType="changeType"
      />
    </template>
    <template v-else>
      <DeclarationGroup
        v-for="(declaration, i) in declarations"
        :class="changeClasses"
        :key="i"
        :declaration="declaration"
        :shouldCaption="hasPlatformVariants"
        :changeType="changeType"
      />
    </template>
    <ConditionalConstraints
      v-if="conformance"
      :constraints="conformance.constraints"
      :prefix="conformance.availabilityPrefix"
    />
  </OnThisPageSection>
</template>

<script>
import ConditionalConstraints from 'docc-render/components/DocumentationTopic/ConditionalConstraints.vue';
import OnThisPageSection from 'docc-render/components/DocumentationTopic/OnThisPageSection.vue';

import DeclarationGroup from 'docc-render/components/DocumentationTopic/PrimaryContent/DeclarationGroup.vue';
import DeclarationDiff
  from 'docc-render/components/DocumentationTopic/PrimaryContent/DeclarationDiff.vue';

import { ChangeTypes } from 'docc-render/constants/Changes';
import { multipleLinesClass } from 'docc-render/constants/multipleLines';

export default {
  name: 'Declaration',
  components: {
    DeclarationDiff,
    DeclarationGroup,
    ConditionalConstraints,
    OnThisPageSection,
  },
  constants: { ChangeTypes, multipleLinesClass },
  inject: ['identifier', 'store'],
  data: ({ store: { state } }) => ({
    state,
    multipleLinesClass,
  }),
  props: {
    conformance: {
      type: Object,
      required: false,
    },
    declarations: {
      type: Array,
      required: true,
    },
  },
  computed: {
    /**
     * Show the captions of DeclarationGroup without changes
     * when there are more than one declarations
     * @returns {boolean}
     */
    hasPlatformVariants() {
      return this.declarations.length > 1;
    },
    /**
     * Returns whether there are declaration changes.
     * @returns {boolean}
     */
    hasModifiedChanges({ declarationChanges }) {
      if (!declarationChanges || !declarationChanges.declaration) return false;

      const changes = declarationChanges.declaration;
      return !!((changes.new || []).length && (changes.previous || []).length);
    },
    /**
     * Returns the API changes for this page
     * @returns {object}
     */
    declarationChanges:
      ({ state: { apiChanges }, identifier }) => apiChanges && apiChanges[identifier],
    /**
     * Returns the type of code change
     * @returns {"added"|"deprecated"|"modified"}
     */
    changeType: ({ declarationChanges, hasModifiedChanges }) => {
      if (!declarationChanges) return undefined;

      const changedDecl = declarationChanges.declaration;
      // if there are no declarations to diff, its most probably an addition
      if (!changedDecl) {
        return declarationChanges.change === ChangeTypes.added
          ? ChangeTypes.added
          : undefined;
      }

      if (hasModifiedChanges) {
        return ChangeTypes.modified;
      }
      return declarationChanges.change;
    },
    /**
     * Returns the appropriate changes classes
     */
    changeClasses: ({ changeType }) => ({
      [`changed changed-${changeType}`]: changeType,
    }),
  },
};
</script>

<style scoped lang="scss">
@import 'docc-render/styles/_core.scss';

.conditional-constraints {
  margin: rem(20px) 0 3rem 0;
}
</style>
