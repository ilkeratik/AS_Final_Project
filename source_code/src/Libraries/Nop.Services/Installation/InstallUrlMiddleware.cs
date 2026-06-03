using Microsoft.AspNetCore.Http;
using Nop.Core;
using Nop.Data;

namespace Nop.Services.Installation;

/// <summary>
/// Represents middleware that checks whether database is installed and redirects to installation URL in otherwise
/// </summary>
public partial class InstallUrlMiddleware
{
    #region Fields

    protected readonly RequestDelegate _next;

    #endregion

    #region Ctor

    public InstallUrlMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    #endregion

    #region Methods

    /// <summary>
    /// Invoke middleware actions
    /// </summary>
    /// <param name="context">HTTP context</param>
    /// <param name="webHelper">Web helper</param>
    /// <returns>A task that represents the asynchronous operation</returns>
    public virtual async Task InvokeAsync(HttpContext context, IWebHelper webHelper)
    {
        //whether database is installed
        if (!DataSettingsManager.IsDatabaseInstalled())
        {
            // Build install URL without accessing database (which may not be configured yet)
            var request = context.Request;
            var scheme = request.Scheme;
            var host = request.Host.Value;
            var pathBase = request.PathBase.Value;
            var storeLocation = $"{scheme}://{host}{pathBase}/";
            var installUrl = $"{storeLocation}{NopInstallationDefaults.InstallPath}";
            
            var currentUrl = webHelper.GetThisPageUrl(false);
            if (!currentUrl.StartsWith(installUrl, StringComparison.InvariantCultureIgnoreCase))
            {
                //redirect
                context.Response.Redirect(installUrl);
                return;
            }
        }

        //or call the next middleware in the request pipeline
        await _next(context);
    }

    #endregion
}