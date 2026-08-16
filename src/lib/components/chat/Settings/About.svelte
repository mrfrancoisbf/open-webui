<script lang="ts">
	import { getOllamaVersion } from '$lib/apis/ollama';
	import { WEBUI_NAME, config } from '$lib/stores';
	import { onMount, getContext } from 'svelte';

	import UserSettingRow from './UserSettingRow.svelte';
	import UserSettingSection from './UserSettingSection.svelte';

	const i18n = getContext('i18n');

	let ollamaVersion = '';

	onMount(async () => {
		ollamaVersion = await getOllamaVersion(localStorage.token).catch((error) => {
			return '';
		});
	});
</script>

<div id="tab-about" class="flex flex-col h-full justify-between text-sm">
	<h2 class="text-sm font-medium text-gray-900 dark:text-white mb-4">À propos de Lielo</h2>

	<div class="flex-1 min-h-0 overflow-y-auto scrollbar-hover pr-1.5">
		<UserSettingSection title="Lielo" first>
			<UserSettingRow description="Secure Business AI">
				<div slot="label" class="flex flex-col text-xs text-gray-600 dark:text-gray-400">
					<div class="flex gap-1 text-sm font-semibold text-gray-900 dark:text-white">
						v1.0 (Édition Entreprise)
					</div>
				</div>
			</UserSettingRow>
		</UserSettingSection>

		{#if ollamaVersion}
			<UserSettingSection title={$i18n.t('Ollama Version')}>
				<div class="text-xs text-gray-600 dark:text-gray-400">
					{ollamaVersion ?? 'N/A'}
				</div>
			</UserSettingSection>
		{/if}

		<UserSettingSection title="Informations & Support">
			<div class="flex flex-col gap-y-2 text-xs text-gray-600 dark:text-gray-400 mb-4">
				<p>
					<strong class="font-medium">Site Web :</strong> 
					<a class="hover:text-gray-900 dark:hover:text-white underline" href="https://mediacod.bf" target="_blank">https://mediacod.bf</a>
				</p>
				<p>
					<strong class="font-medium">Support :</strong> 
					<a class="hover:text-gray-900 dark:hover:text-white underline" href="mailto:contact@mediacod.bf">contact@mediacod.bf</a>
				</p>
			</div>

			<div class="text-xs text-gray-500 dark:text-gray-400 mt-4 leading-relaxed">
				Développé et propulsé au Burkina Faso par <strong class="text-gray-700 dark:text-gray-300">MEDIACOD-BF</strong>.
			</div>
			
			<div class="text-xs text-gray-400 dark:text-gray-500 mt-1">
				Copyright &copy; {new Date().getFullYear()} Tous droits réservés.
			</div>
		</UserSettingSection>
	</div>
</div>
