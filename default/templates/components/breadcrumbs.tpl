<nav id="breadcrumbs" class="w-full text-gray-700 md:hidden">
  <div class="flex justify-left">
    <div class="w-full px-2 py-2 bg-gray-50">
      <ul class="flex flex-wrap text-lg">
        <li class="inline-flex items-center">
          <ema:metadata>
            <with var="template">
              <img style="width: 1rem;" src="${value:iconUrl}" />
            </with>
          </ema:metadata>
        </li>
        <ema:breadcrumbs>
          <each-crumb>
            <li class="inline-flex items-center">
              <a class="px-1 font-bold" href="${crumb:url}">
                <crumb:title />
              </a>
              <svg fill="currentColor" viewBox="0 0 20 20" class="w-auto h-5 text-gray-400">
                <path fill-rule="evenodd"
                  d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                  clip-rule="evenodd"></path>
              </svg>
            </li>
          </each-crumb>
        </ema:breadcrumbs>
      </ul>
    </div>
    <button
      class="inline px-3 py-1 text-xl leading-none text-white bg-transparent border border-transparent border-solid rounded outline-none cursor-pointer md:hidden focus:outline-none"
      type="button" onclick="toggleHidden('sidebar');toggleFlex('container')">
      <svg xmlns="http://www.w3.org/2000/svg" style="width: 1rem;" class="hover:text-${theme}-700"
        fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M4 6h16M4 12h16M4 18h16" />
      </svg>
    </button>
    <script>
      function toggleHidden(collapseID) {
        document.getElementById(collapseID).classList.toggle("hidden");
      }
      function toggleFlex(collapseID) {
        document.getElementById(collapseID).classList.toggle("flex");
      }
    </script>
  </div>
</nav>